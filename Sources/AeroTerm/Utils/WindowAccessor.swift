import SwiftUI
import AppKit
import QuartzCore

public enum AppWindowLayout {
    public static let splashSize = NSSize(width: 780, height: 520)
    public static let wizardSize = NSSize(width: 840, height: 600)
    public static let workbenchSize = NSSize(width: 1180, height: 720)
    public static let workbenchMinSize = NSSize(width: 960, height: 600)
}

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
        guard let window = nsView.window,
              !window.inLiveResize,
              !WindowChrome.isUserLiveResizing
        else { return }
        self.callback(window)
    }
}

@MainActor
public final class FullScreenWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    public static let shared = FullScreenWindowDelegate()

    static func attach(to window: NSWindow) {
        if WindowChrome.isDetachedWindow(window) { return }
        if window.delegate !== shared {
            window.delegate = shared
        }
    }

    public func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
        nil
    }

    public func windowWillEnterFullScreen(_ notification: Notification) {
        if SessionManager.shared.isShowingStartupSplash {
            return
        }
        applyFullScreenChrome(true)
        if let window = notification.object as? NSWindow {
            window.toolbar?.isVisible = false
            relayoutWorkspace(window)
        }
    }

    public func windowDidEnterFullScreen(_ notification: Notification) {
        if SessionManager.shared.isShowingStartupSplash, let window = notification.object as? NSWindow {
            window.toggleFullScreen(nil)
            return
        }
        applyFullScreenChrome(true)
        if let window = notification.object as? NSWindow {
            window.toolbar?.isVisible = false
            relayoutWorkspace(window, delayed: true)
        }
    }

    public func windowWillExitFullScreen(_ notification: Notification) {
        applyFullScreenChrome(false)
        if let window = notification.object as? NSWindow {
            window.toolbar?.isVisible = true
        }
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        applyFullScreenChrome(false)
        if let window = notification.object as? NSWindow {
            window.toolbar?.isVisible = true
            WindowChrome.sync(window)
            relayoutWorkspace(window, delayed: true)
        }
    }

    public func windowWillStartLiveResize(_ notification: Notification) {
        WindowChrome.beginUserLiveResize()
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        WindowChrome.endUserLiveResize()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        reapplySplashChrome(notification)
    }

    public func windowDidResignKey(_ notification: Notification) {
        reapplySplashChrome(notification)
    }

    public func windowDidBecomeMain(_ notification: Notification) {
        reapplySplashChrome(notification)
    }

    public func windowDidResignMain(_ notification: Notification) {
        reapplySplashChrome(notification)
    }

    private func applyFullScreenChrome(_ isFullScreen: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            SessionManager.shared.isFullScreen = isFullScreen
            SessionManager.shared.columnVisibility = isFullScreen ? .detailOnly : .all
        }
    }

    private func relayoutWorkspace(_ window: NSWindow, delayed: Bool = false) {
        WorkspaceTilingNSView.relayoutAll(in: window)
        guard delayed else { return }
        DispatchQueue.main.async {
            WorkspaceTilingNSView.relayoutAll(in: window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            WorkspaceTilingNSView.relayoutAll(in: window)
        }
    }

    private func reapplySplashChrome(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        WindowChrome.applyAfterFocusChange(to: window)
    }

    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if SessionManager.shared.isShowingStartupSplash {
            if SessionManager.shared.isShowingNewConnectionWizard {
                return AppWindowLayout.wizardSize
            }
            return AppWindowLayout.splashSize
        }
        return frameSize
    }

    public func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        if SessionManager.shared.isShowingStartupSplash {
            return false
        }
        return true
    }
}
