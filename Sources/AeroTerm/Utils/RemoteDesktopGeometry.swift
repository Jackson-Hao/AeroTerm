import AppKit
import CoreGraphics
import ObjectiveC
@preconcurrency import RoyalVNCKit

@MainActor
enum RemoteDesktopGeometry {
    static let minWidth: CGFloat = 640
    static let minHeight: CGFloat = 480
    static let maxWidth: CGFloat = 8192
    static let maxHeight: CGFloat = 8192

    static func fallbackPointSize() -> CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(
            width: min(maxWidth, max(minWidth, screen.width - 280)),
            height: min(maxHeight, max(minHeight, screen.height - 96))
        )
    }

    static func clampedPointSize(_ size: CGSize) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite else { return nil }
        let width = size.width.rounded()
        let height = size.height.rounded()
        guard width >= 64, height >= 64 else { return nil }
        return CGSize(
            width: min(maxWidth, max(minWidth, width)),
            height: min(maxHeight, max(minHeight, height))
        )
    }

    static func vncFramebufferSize(pointSize: CGSize) -> (width: UInt16, height: UInt16)? {
        guard let size = clampedPointSize(pointSize) else { return nil }
        var width = Int(size.width)
        let height = Int(size.height)
        if width % 2 != 0 { width -= 1 }
        guard width >= Int(minWidth), height >= Int(minHeight) else { return nil }
        return (UInt16(clamping: width), UInt16(clamping: height))
    }

    static func backingScale(for view: NSView?) -> CGFloat {
        let scale = view?.window?.backingScaleFactor
            ?? view?.window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        return scale.isFinite && scale > 0 ? scale : 2
    }
}

@MainActor
final class ViewportResizeDebouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private var lastSent: (CGSize, CGFloat)?

    init(delay: TimeInterval = 0.18) {
        self.delay = delay
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }

    func schedule(
        size: CGSize,
        scale: CGFloat,
        immediate: Bool = false,
        fire: @escaping (CGSize, CGFloat) -> Void
    ) {
        workItem?.cancel()
        workItem = nil
        guard let clamped = RemoteDesktopGeometry.clampedPointSize(size) else { return }
        let safeScale = scale.isFinite && scale > 0 ? scale : 2
        if let lastSent,
           abs(lastSent.0.width - clamped.width) < 2,
           abs(lastSent.0.height - clamped.height) < 2,
           abs(lastSent.1 - safeScale) < 0.05
        {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.lastSent = (clamped, safeScale)
            fire(clamped, safeScale)
        }
        workItem = work
        if immediate {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}

enum VNCDesktopSizeClient {
    private static let selector = NSSelectorFromString("vnc_requestDesktopSizeWithWidth:height:")

    static func request(_ connection: VNCConnection, width: UInt16, height: UInt16) {
        guard connection.responds(to: selector),
              let method = class_getInstanceMethod(VNCConnection.self, selector)
        else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt16, UInt16) -> Void
        unsafeBitCast(method_getImplementation(method), to: Fn.self)(connection, selector, width, height)
    }
}
