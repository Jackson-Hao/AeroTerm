import SwiftUI
import AppKit

public struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    public init(callback: @escaping (NSWindow) -> Void) {
        self.callback = callback
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            self.callback(window)
        }
    }
}

@MainActor
public final class FullScreenWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    public static let shared = FullScreenWindowDelegate()

    // 彻底拦截系统 Globe+F / Fn+F 全屏请求
    public func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
        if SessionManager.shared.isShowingStartupSplash {
            return nil
        }
        return nil
    }

    public func windowWillEnterFullScreen(_ notification: Notification) {
        if SessionManager.shared.isShowingStartupSplash {
            return
        }
        SessionManager.shared.isFullScreen = true
        SessionManager.shared.columnVisibility = .detailOnly
    }

    public func windowDidEnterFullScreen(_ notification: Notification) {
        // 如果在 Splash 状态下意外触发了全屏，立即强制退出全屏
        if SessionManager.shared.isShowingStartupSplash, let window = notification.object as? NSWindow {
            window.toggleFullScreen(nil)
        }
    }

    public func windowWillExitFullScreen(_ notification: Notification) {
        SessionManager.shared.isFullScreen = false
        SessionManager.shared.columnVisibility = .all
    }

    // 启动页绝对锁死尺寸，主页面正常拉伸
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if SessionManager.shared.isShowingStartupSplash {
            return NSSize(width: 780, height: 480)
        }
        return frameSize
    }

    // 启动页绝对禁止任何 Zoom / 标题栏双击全屏操作
    public func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        if SessionManager.shared.isShowingStartupSplash {
            return false
        }
        return true
    }
}
