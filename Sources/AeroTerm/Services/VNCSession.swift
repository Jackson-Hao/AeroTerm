import AppKit
import Combine
import ObjectiveC
@preconcurrency import RoyalVNCKit

@MainActor
public final class VNCDesktopSession: ObservableObject {
    public private(set) var sessionID: UUID
    public let connection: VNCConnection
    @Published public var isAlive = false
    @Published public var statusText = "Connecting…"
    @Published public var lastError: String?

    private let password: String
    private let username: String
    let container = VNCHostView(frame: .zero)
    private var framebufferView: VNCCAFramebufferView?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var suppressDisconnectNotify = false
    private let viewportDebouncer = ViewportResizeDebouncer()
    private var lastRequestedSize: (width: UInt16, height: UInt16)?
    private var supportsDesktopResize = false
    private let qualityPrefs: VNCQualityPreferences
    private var displaySettings: DesktopDisplaySettings
    private var currentColorDepth: VNCConnection.Settings.ColorDepth

    public init(
        sessionID: UUID,
        host: String,
        port: Int,
        username: String,
        password: String,
        display: DesktopDisplaySettings = .default
    ) {
        self.sessionID = sessionID
        self.username = username
        self.password = password
        self.displaySettings = display
        let qualityPrefs = VNCQualityPreferences(quality: display.quality)
        self.qualityPrefs = qualityPrefs
        let colorDepth: VNCConnection.Settings.ColorDepth = display.quality == .low ? .depth16Bit : .depth24Bit
        self.currentColorDepth = colorDepth
        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: host,
            port: UInt16(clamping: port),
            isShared: true,
            isScalingEnabled: true,
            useDisplayLink: true,
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,
            isClipboardRedirectionEnabled: true,
            colorDepth: colorDepth,
            frameEncodings: display.quality == .low
                ? [.zlib, .hextile, .coRRE, .rre]
                : .default
        )
        let connection = VNCConnection(
            settings: settings,
            logger: QuietVNCLogger(),
            framebufferAllocator: nil,
            context: Unmanaged.passUnretained(qualityPrefs).toOpaque()
        )
        self.connection = connection
        connection.delegate = self
        container.onViewportChange = { [weak self] size, _, immediate in
            self?.updateViewport(size: size, immediate: immediate)
        }
    }

    public func rebind(sessionID: UUID) {
        self.sessionID = sessionID
    }

    public func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuation = continuation
            connection.connect()
        }
    }

    public func shutdown() {
        viewportDebouncer.cancel()
        suppressDisconnectNotify = true
        finishConnect(.failure(VNCConnectError.cancelled))
        isAlive = false
        container.onViewportChange = nil
        connection.disconnect()
    }

    public func updateViewport(size: CGSize, immediate: Bool = false) {
        guard supportsDesktopResize else { return }
        viewportDebouncer.schedule(size: size, scale: 1, immediate: immediate) { [weak self] size, _ in
            self?.requestDesktopSize(size)
        }
    }

    private func requestDesktopSize(_ size: CGSize) {
        guard isAlive, let framebufferSize = RemoteDesktopGeometry.vncFramebufferSize(pointSize: size) else { return }
        if let lastRequestedSize,
           lastRequestedSize.width == framebufferSize.width,
           lastRequestedSize.height == framebufferSize.height
        {
            return
        }
        lastRequestedSize = framebufferSize
        VNCDesktopSizeClient.request(connection, width: framebufferSize.width, height: framebufferSize.height)
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        guard let connectContinuation else { return }
        self.connectContinuation = nil
        connectContinuation.resume(with: result)
    }

    private func handleState(status: VNCConnection.Status, errorMessage: String?) {
        switch status {
        case .connecting:
            statusText = "Connecting…"
        case .connected:
            statusText = "Connected"
            isAlive = true
            lastError = nil
            finishConnect(.success(()))
        case .disconnecting:
            statusText = "Disconnecting…"
        case .disconnected:
            let wasAlive = isAlive
            isAlive = false
            if let errorMessage, !errorMessage.isEmpty {
                lastError = errorMessage
                statusText = errorMessage
                finishConnect(.failure(VNCConnectError.failed(errorMessage)))
            } else {
                statusText = "Disconnected"
                finishConnect(.failure(VNCConnectError.disconnected))
            }
            if !suppressDisconnectNotify, wasAlive || connectContinuation == nil {
                SessionManager.shared.markSessionDisconnected(id: sessionID)
            }
        @unknown default:
            break
        }
    }

    private func installFramebuffer(_ framebuffer: VNCFramebuffer) {
        let wasFirstResponder = framebufferView?.window?.firstResponder === framebufferView
        framebufferView?.removeFromSuperview()
        let view = VNCCAFramebufferView(
            frame: container.bounds,
            framebuffer: framebuffer,
            connection: connection,
            connectionDelegate: self
        )
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        framebufferView = view
        if wasFirstResponder {
            container.window?.makeFirstResponder(view)
        }
        if !framebuffer.screens.isEmpty {
            supportsDesktopResize = true
            if let size = container.currentPointSize {
                requestDesktopSize(size)
            }
        }
        applyRefreshRate()
    }

    public func applyDisplaySettings(_ settings: DesktopDisplaySettings) {
        displaySettings = settings
        qualityPrefs.apply(settings.quality)
        let depth: VNCConnection.Settings.ColorDepth = settings.quality == .low ? .depth16Bit : .depth24Bit
        if currentColorDepth != depth {
            currentColorDepth = depth
            connection.updateColorDepth(depth)
        }
        applyRefreshRate()
    }

    private func applyRefreshRate() {
        guard let framebufferView else { return }
        VNCFramePacingClient.setMinimumInterval(framebufferView, displaySettings.refreshRate.frameInterval)
    }
}

final class VNCQualityPreferences: NSObject {
    @objc var jpegQualityLevel: Int
    @objc var compressionLevel: Int

    init(quality: DesktopQuality) {
        jpegQualityLevel = quality.vncJpegQuality
        compressionLevel = quality.vncCompression
        super.init()
    }

    func apply(_ quality: DesktopQuality) {
        jpegQualityLevel = quality.vncJpegQuality
        compressionLevel = quality.vncCompression
    }
}

enum VNCFramePacingClient {
    private static let selector = NSSelectorFromString("aeroSetMinimumFrameInterval:")

    static func setMinimumInterval(_ view: VNCCAFramebufferView, _ interval: TimeInterval) {
        guard view.responds(to: selector),
              let method = class_getInstanceMethod(VNCCAFramebufferView.self, selector)
        else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Double) -> Void
        unsafeBitCast(method_getImplementation(method), to: Fn.self)(view, selector, interval)
    }
}

extension VNCDesktopSession: VNCConnectionDelegate {
    public nonisolated func connection(
        _ connection: VNCConnection,
        stateDidChange connectionState: VNCConnection.ConnectionState
    ) {
        let status = connectionState.status
        let errorMessage = connectionState.error?.localizedDescription
        Task { @MainActor in
            handleState(status: status, errorMessage: errorMessage)
        }
    }

    public nonisolated func connection(
        _ connection: VNCConnection,
        credentialFor authenticationType: VNCAuthenticationType,
        completion: @escaping ((any VNCCredential)?) -> Void
    ) {
        if authenticationType.requiresUsername {
            completion(VNCUsernamePasswordCredential(username: username, password: password))
        } else if authenticationType.requiresPassword {
            completion(VNCPasswordCredential(password: password))
        } else {
            completion(nil)
        }
    }

    public nonisolated func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor in
            installFramebuffer(framebuffer)
        }
    }

    public nonisolated func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor in
            installFramebuffer(framebuffer)
        }
    }

    public nonisolated func connection(
        _ connection: VNCConnection,
        didUpdateFramebuffer framebuffer: VNCFramebuffer,
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16
    ) {}

    public nonisolated func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {}
}

final class VNCHostView: NSView {
    var onViewportChange: ((CGSize, CGFloat, Bool) -> Void)?

    var currentPointSize: CGSize? {
        RemoteDesktopGeometry.clampedPointSize(bounds.size)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        emitViewport()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        emitViewport()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        emitViewport(immediate: true)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        emitViewport(immediate: true)
    }

    func emitViewport(immediate: Bool = false) {
        guard let size = currentPointSize else { return }
        onViewportChange?(size, RemoteDesktopGeometry.backingScale(for: self), immediate)
    }
}

enum VNCConnectError: LocalizedError {
    case cancelled
    case disconnected
    case timeout
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "VNC connection cancelled."
        case .disconnected: return "VNC session disconnected."
        case .timeout: return "VNC connection timed out."
        case .failed(let message): return message
        }
    }
}

final class QuietVNCLogger: VNCLogger {
    var isDebugLoggingEnabled = false
    func logDebug(_ message: @autoclosure () -> String) {}
    func logInfo(_ message: String) {}
    func logWarning(_ message: String) {}
    func logError(_ message: String) {}
}
