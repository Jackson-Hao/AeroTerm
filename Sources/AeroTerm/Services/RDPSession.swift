import AppKit
import Combine
import CoreGraphics
import RDPKit

private extension DesktopQuality {
    var rdpGraphicsProfile: RDPGraphicsCapabilityProfile {
        switch self {
        case .high: return .automatic
        case .balanced: return .avc420
        case .low: return .avcThinClient
        }
    }
}

@MainActor
public final class RDPDesktopSession: ObservableObject {
    public private(set) var sessionID: UUID
    @Published public var isAlive = false
    @Published public var statusText = "Connecting…"
    @Published public var lastError: String?

    let canvas = RDPCanvasView(frame: .zero)
    private let cancellation = RDPConnectionCancellation()
    private var runTask: Task<Void, Never>?
    private var displayControl: RDPDisplayControlSession?
    private var lastDisplayRequest: RDPDisplayRequest?
    private let viewportDebouncer = ViewportResizeDebouncer()
    private var displaySettings: DesktopDisplaySettings = .default
    fileprivate var minFrameInterval: TimeInterval = DesktopRefreshRate.hz60.frameInterval

    public init(sessionID: UUID) {
        self.sessionID = sessionID
        canvas.onViewportChange = { [weak self] size, scale, immediate in
            self?.updateViewport(size: size, backingScale: scale, immediate: immediate)
        }
    }

    public func rebind(sessionID: UUID) {
        self.sessionID = sessionID
    }

    /// Accept `DOMAIN\\user` or `user@upn` from the account username field.
    static func splitDomainUser(_ raw: String) -> (username: String, domain: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = trimmed.firstIndex(of: "\\") {
            let domain = String(trimmed[..<slash])
            let user = String(trimmed[trimmed.index(after: slash)...])
            if !domain.isEmpty, !user.isEmpty {
                return (user, domain)
            }
        }
        return (trimmed, nil)
    }

    public func start(
        host: String,
        port: Int,
        username: String,
        password: String,
        desktopSize: CGSize? = nil,
        display: DesktopDisplaySettings = .default
    ) async throws {
        displaySettings = display
        minFrameInterval = display.refreshRate.frameInterval
        statusText = "Connecting…"
        lastError = nil
        let split = Self.splitDomainUser(username)
        let credentials = try RDPCredentials.validated(
            username: split.username,
            domain: split.domain,
            password: password
        )
        let initialSize = desktopSize ?? canvas.currentPointSize ?? RemoteDesktopGeometry.fallbackPointSize()
        let initialScale = RemoteDesktopGeometry.backingScale(for: canvas)
        let displayRequest = RDPDisplayRequest(pointSize: initialSize, backingScaleFactor: initialScale)
        lastDisplayRequest = displayRequest
        let configuration = RDPConnectionConfiguration(
            host: host,
            port: UInt16(clamping: port),
            credentials: credentials,
            timeoutSeconds: 15,
            hideCertificateWarnings: true,
            graphicsFrameCaptureLimit: nil,
            desktopWidth: UInt16(clamping: displayRequest.width),
            desktopHeight: UInt16(clamping: displayRequest.height),
            clipboardEnabled: true,
            audioPlaybackEnabled: false,
            graphicsCapabilityProfile: display.quality.rdpGraphicsProfile
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ConnectGate()
            let sink = RDPSessionSink(self)
            runTask = Task.detached { [cancellation] in
                let decoder = RDPVideoToolboxFrameDecoder()
                let report = RDPPreflightClient().run(
                    configuration: configuration,
                    onGraphicsFrame: { snapshot in
                        do {
                            // Bitmap frames already sit in BGRA; wrapping them avoids a
                            // full-screen Core Image conversion on the I/O thread (that
                            // conversion also delayed RemoteFX frame ACKs).
                            let image = try RDPBitmapCGImage.make(snapshot)
                                ?? decoder.decode(snapshot)
                            sink.present(image)
                            gate.succeed(continuation)
                        } catch {
                            // Skip a bad frame instead of tearing the session down.
                        }
                    },
                    onInputReady: { input in
                        sink.ready(input)
                        gate.succeed(continuation)
                    },
                    onDisplayControlReady: { display in
                        sink.displayControl(display)
                    },
                    cancellation: cancellation,
                    shouldCancel: { cancellation.isCancelled }
                )
                if cancellation.isCancelled {
                    gate.fail(continuation, RDPConnectError.cancelled)
                    return
                }
                let message = report.error
                gate.fail(continuation, RDPConnectError.failed(message ?? "RDP session ended."))
                sink.closed(message)
            }
        }
    }

    public func shutdown() {
        viewportDebouncer.cancel()
        cancellation.cancel()
        runTask?.cancel()
        isAlive = false
        displayControl = nil
        canvas.inputSession = nil
        canvas.onViewportChange = nil
    }

    public func applyDisplaySettings(_ settings: DesktopDisplaySettings) {
        displaySettings = settings
        minFrameInterval = settings.refreshRate.frameInterval
    }

    public func updateViewport(size: CGSize, backingScale: CGFloat, immediate: Bool = false) {
        viewportDebouncer.schedule(size: size, scale: backingScale, immediate: immediate) { [weak self] size, scale in
            self?.sendDisplayRequest(RDPDisplayRequest(pointSize: size, backingScaleFactor: scale))
        }
    }

    fileprivate func attachDisplayControl(_ session: RDPDisplayControlSession) {
        displayControl = session
        if let lastDisplayRequest {
            session.send(lastDisplayRequest)
        } else if let size = canvas.currentPointSize {
            sendDisplayRequest(
                RDPDisplayRequest(pointSize: size, backingScaleFactor: RemoteDesktopGeometry.backingScale(for: canvas))
            )
        }
    }

    private func sendDisplayRequest(_ request: RDPDisplayRequest) {
        if lastDisplayRequest == request, displayControl != nil {
            return
        }
        lastDisplayRequest = request
        displayControl?.send(request)
    }

    fileprivate func markConnected() {
        isAlive = true
        statusText = "Connected"
        lastError = nil
    }

    fileprivate func handleRemoteClose(message: String? = nil) {
        guard isAlive else { return }
        isAlive = false
        lastError = message ?? LocalizationManager.lookup("rdp_disconnected")
        statusText = lastError ?? "Disconnected"
        canvas.inputSession = nil
        SessionManager.shared.markSessionDisconnected(id: sessionID)
    }
}

private final class RDPSessionSink: @unchecked Sendable {
    private weak var session: RDPDesktopSession?
    private let lock = NSLock()
    private var latestImage: CGImage?
    private var presentScheduled = false
    private var lastPresentAt: TimeInterval = 0

    init(_ session: RDPDesktopSession) {
        self.session = session
    }

    func present(_ image: CGImage) {
        lock.lock()
        latestImage = image
        let shouldSchedule = !presentScheduled
        if shouldSchedule {
            presentScheduled = true
        }
        lock.unlock()
        guard shouldSchedule else { return }
        // Coalesce to one blit per main-run-loop turn so classic bitmap
        // PDUs cannot flood Core Animation.
        Task { @MainActor [weak self] in
            self?.flushPresent()
        }
    }

    @MainActor
    private func flushPresent() {
        let interval = session?.minFrameInterval ?? 0
        let now = ProcessInfo.processInfo.systemUptime
        let wait = interval - (now - lastPresentAt)
        if wait > 0.004 {
            Task { @MainActor [weak self] in
                let nanos = UInt64(wait * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                self?.flushPresent()
            }
            return
        }
        lock.lock()
        let image = latestImage
        latestImage = nil
        presentScheduled = false
        lock.unlock()
        guard let image else { return }
        lastPresentAt = ProcessInfo.processInfo.systemUptime
        session?.canvas.present(image)
        session?.markConnected()
    }

    func ready(_ input: RDPInputSession) {
        Task { @MainActor [weak self] in
            self?.session?.canvas.inputSession = input
            self?.session?.markConnected()
        }
    }

    func displayControl(_ control: RDPDisplayControlSession) {
        Task { @MainActor [weak self] in
            self?.session?.attachDisplayControl(control)
        }
    }

    func closed(_ message: String?) {
        Task { @MainActor [weak self] in
            self?.session?.handleRemoteClose(message: message)
        }
    }
}

private enum RDPBitmapCGImage {
    static func make(_ frame: RDPGraphicsFrameSnapshot) -> CGImage? {
        guard frame.contentKind == .bitmap,
              let data = frame.decodedBitmapData,
              let bytesPerRow = frame.decodedBitmapBytesPerRow
        else {
            return nil
        }
        let width = Int(frame.width)
        let height = Int(frame.height)
        guard width > 0,
              height > 0,
              bytesPerRow >= width * 4,
              data.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: data as CFData)
        else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.noneSkipFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private final class ConnectGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func succeed(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume()
    }

    func fail(_ continuation: CheckedContinuation<Void, Error>, _ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(throwing: error)
    }
}

enum RDPConnectError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "RDP connection cancelled."
        case .failed(let message): return message
        }
    }
}

final class RDPCanvasView: NSView {
    var inputSession: RDPInputSession?
    var onDisconnect: (() -> Void)?
    var onViewportChange: ((CGSize, CGFloat, Bool) -> Void)?
    private var image: CGImage?
    private var tracker = RDPInputStateTracker()
    private var lastMoveSentAt: TimeInterval = 0
    private var lastModifierFlags: NSEvent.ModifierFlags = []

    var currentPointSize: CGSize? {
        RemoteDesktopGeometry.clampedPointSize(bounds.size)
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
        autoresizingMask = [.width, .height]
    }

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self
        ))
    }

    func emitViewport(immediate: Bool = false) {
        guard let size = currentPointSize else { return }
        onViewportChange?(size, RemoteDesktopGeometry.backingScale(for: self), immediate)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present(_ image: CGImage) {
        self.image = image
        layer?.contents = image
    }

    private var fittedImageRect: CGRect {
        guard let image else { return bounds }
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }

    override func mouseMoved(with event: NSEvent) { sendMove(event) }
    override func mouseDragged(with event: NSEvent) { sendMove(event) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendButton(.left, isDown: true, event: event)
    }
    override func mouseUp(with event: NSEvent) { sendButton(.left, isDown: false, event: event) }
    override func rightMouseDown(with event: NSEvent) { sendButton(.right, isDown: true, event: event) }
    override func rightMouseUp(with event: NSEvent) { sendButton(.right, isDown: false, event: event) }
    override func otherMouseDown(with event: NSEvent) { sendButton(.middle, isDown: true, event: event) }
    override func otherMouseUp(with event: NSEvent) { sendButton(.middle, isDown: false, event: event) }

    override func scrollWheel(with event: NSEvent) {
        let point = remotePoint(for: event)
        let rotation = Int(event.scrollingDeltaY.rounded())
        guard rotation != 0 else { return }
        inputSession?.send(.verticalWheel(rotation: rotation, x: point.x, y: point.y))
    }

    override func keyDown(with event: NSEvent) {
        sendKey(event, released: false)
    }

    override func keyUp(with event: NSEvent) {
        sendKey(event, released: true)
    }

    override func flagsChanged(with event: NSEvent) {
        sendModifierChange(event)
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            lastModifierFlags = NSEvent.modifierFlags.intersection(Self.trackedModifiers)
            inputSession?.send(.synchronize(toggleFlags: toggleFlags(from: NSEvent.modifierFlags)))
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        releasePressedKeys()
        return super.resignFirstResponder()
    }

    private func sendMove(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMoveSentAt < 1.0 / 40.0 {
            return
        }
        lastMoveSentAt = now
        let point = remotePoint(for: event)
        inputSession?.send(tracker.pointerMove(to: point))
    }

    private func sendButton(_ button: RDPPointerButton, isDown: Bool, event: NSEvent) {
        let point = remotePoint(for: event)
        if let input = tracker.pointerButton(button, isDown: isDown, at: point) {
            inputSession?.send(input)
        }
    }

    private static let trackedModifiers: NSEvent.ModifierFlags = [
        .shift, .control, .option, .command, .capsLock
    ]

    private func sendKey(_ event: NSEvent, released: Bool) {
        if RDPKeyMap.modifierKeyCodes.contains(event.keyCode) {
            return
        }
        if let scancode = RDPKeyMap.scancode(forMacKeyCode: event.keyCode) {
            inputSession?.send(
                tracker.keyboard(
                    scancode: scancode,
                    isReleased: released,
                    isRepeat: event.isARepeat && released == false
                )
            )
            return
        }

        guard let scalar = event.characters?.unicodeScalars.first,
              scalar.value >= 32,
              scalar.value != 0x7F,
              RDPKeyMap.isFunctionKeyScalar(scalar) == false
        else { return }
        inputSession?.send(
            .unicode(codeUnit: UInt16(truncatingIfNeeded: scalar.value), isReleased: released)
        )
    }

    private func sendModifierChange(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.trackedModifiers)
        let keyCode = event.keyCode

        if flags.contains(.capsLock) != lastModifierFlags.contains(.capsLock) {
            let down = tracker.keyboard(scancode: RDPKeyMap.capsLock, isReleased: false)
            let up = tracker.keyboard(scancode: RDPKeyMap.capsLock, isReleased: true)
            inputSession?.send([
                down,
                up,
                .synchronize(toggleFlags: toggleFlags(from: flags))
            ])
        }

        sendModifier(
            flag: .shift,
            flags: flags,
            keyCode: keyCode,
            left: RDPKeyMap.leftShift,
            right: RDPKeyMap.rightShift,
            rightCode: RDPKeyMap.rightShiftKeyCode
        )
        sendModifier(
            flag: .control,
            flags: flags,
            keyCode: keyCode,
            left: RDPKeyMap.leftControl,
            right: RDPKeyMap.rightControl,
            rightCode: RDPKeyMap.rightControlKeyCode
        )
        sendModifier(
            flag: .option,
            flags: flags,
            keyCode: keyCode,
            left: RDPKeyMap.leftAlt,
            right: RDPKeyMap.rightAlt,
            rightCode: RDPKeyMap.rightOptionKeyCode
        )
        sendModifier(
            flag: .command,
            flags: flags,
            keyCode: keyCode,
            left: RDPKeyMap.leftWin,
            right: RDPKeyMap.rightWin,
            rightCode: RDPKeyMap.rightCommandKeyCode
        )

        lastModifierFlags = flags
    }

    private func sendModifier(
        flag: NSEvent.ModifierFlags,
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16,
        left: RDPKeyboardScancode,
        right: RDPKeyboardScancode,
        rightCode: UInt16
    ) {
        let now = flags.contains(flag)
        let was = lastModifierFlags.contains(flag)
        guard now != was else { return }
        let scancode = keyCode == rightCode ? right : left
        inputSession?.send(tracker.keyboard(scancode: scancode, isReleased: !now))
    }

    private func toggleFlags(from flags: NSEvent.ModifierFlags) -> RDPToggleKeyFlags {
        flags.contains(.capsLock) ? .capsLock : []
    }

    private func releasePressedKeys() {
        let events = tracker.releasePressedInputs()
        if events.isEmpty == false {
            inputSession?.send(events)
        }
        lastModifierFlags = []
    }

    private func remotePoint(for event: NSEvent) -> RDPRemotePoint {
        let local = convert(event.locationInWindow, from: nil)
        let rect = fittedImageRect
        let imageWidth = CGFloat(image?.width ?? Int(max(rect.width, 1)))
        let imageHeight = CGFloat(image?.height ?? Int(max(rect.height, 1)))
        let x = (local.x - rect.minX) / max(rect.width, 1) * imageWidth
        let y = (local.y - rect.minY) / max(rect.height, 1) * imageHeight
        return RDPRemotePoint(
            x: UInt16(clamping: Int(min(max(x, 0), imageWidth))),
            y: UInt16(clamping: Int(min(max(y, 0), imageHeight)))
        )
    }

}
