import AppKit

/// 窗口外观只有两种，且只从 `sync` 进入：
/// - splash：无系统顶栏（启动页 / 其上的向导）
/// - workbench：统一透明系统顶栏（主页面）
@MainActor
enum WindowChrome {
    private enum Mode {
        case splash
        case workbench
    }

    private static var mode: Mode?
    private static var didApplyInitialWorkbenchSize = false
    private static var userLiveResizeCount = 0
    private static var suppressSyncUntil: TimeInterval = 0

    static var isUserLiveResizing: Bool {
        userLiveResizeCount > 0 || ProcessInfo.processInfo.systemUptime < suppressSyncUntil
    }

    static func beginUserLiveResize() {
        userLiveResizeCount += 1
    }

    static func endUserLiveResize() {
        userLiveResizeCount = max(0, userLiveResizeCount - 1)
        suppressSyncUntil = ProcessInfo.processInfo.systemUptime + 0.35
    }

    static func suppressSyncBriefly() {
        suppressSyncUntil = ProcessInfo.processInfo.systemUptime + 0.35
    }

    static func isDetachedWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("AeroTerm.Detached.") == true
    }

    static func applyDetached(to window: NSWindow) {
        if isUserLiveResizing || window.inLiveResize { return }
        if window.styleMask.contains(.fullScreen) {
            if window.toolbar?.isVisible != false {
                window.toolbar?.isVisible = false
            }
            return
        }
        window.minSize = NSSize(width: 560, height: 360)
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.isRestorable = false
        if isWorkbenchAppearanceHealthy(window), window.toolbar?.isVisible == true {
            return
        }
        applyWorkbenchAppearance(to: window, forceToolbarVisible: true)
    }

    /// 唯一入口。模式没变时只做轻量校正，不重画顶栏。
    static func sync(_ window: NSWindow) {
        if isUserLiveResizing || window.inLiveResize { return }
        if isDetachedWindow(window) {
            applyDetached(to: window)
            return
        }
        if window.identifier == nil {
            window.identifier = NSUserInterfaceItemIdentifier("AeroTerm.Main")
        }
        let target: Mode = usesSplashChrome ? .splash : .workbench
        if mode == target {
            switch target {
            case .splash:
                applySplash(to: window)
            case .workbench:
                restoreWorkbenchIfNeeded(on: window)
            }
            return
        }

        switch target {
        case .splash:
            applySplash(to: window)
        case .workbench:
            applyWorkbench(to: window, resize: true)
        }
        mode = target
    }

    /// 失焦 / 再激活：只重套启动页，主页面不动。
    private static var usesSplashChrome: Bool {
        SessionManager.shared.isShowingStartupSplash
    }

    static func applyAfterFocusChange(to window: NSWindow) {
        guard usesSplashChrome else { return }
        applySplash(to: window)
        mode = .splash
    }

    // MARK: - Splash

    private static func applySplash(to window: NSWindow) {
        let size = SessionManager.shared.isShowingNewConnectionWizard
            ? AppWindowLayout.wizardSize
            : AppWindowLayout.splashSize
        if window.minSize != size || window.maxSize != size || window.styleMask.contains(.resizable) {
            lockFixed(window, size: size)
        }
        if window.standardWindowButton(.closeButton)?.isHidden != true
            || window.standardWindowButton(.closeButton)?.superview?.isHidden != true {
            hideSystemTitlebar(on: window)
        }
        mode = .splash
    }

    // MARK: - Workbench

    private static func applyWorkbench(to window: NSWindow, resize: Bool) {
        revealTitlebarViews(in: window)
        applyWorkbenchAppearance(to: window)

        window.minSize = AppWindowLayout.workbenchMinSize
        window.contentMinSize = AppWindowLayout.workbenchMinSize
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.isRestorable = false

        if resize {
            applyInitialWorkbenchSizeIfNeeded(window)
        }
        mode = .workbench
    }

    /// 侧栏折叠、SwiftUI 刷新时可能把透明顶栏或红绿灯打乱；只恢复属性，不定尺寸。
    private static func restoreWorkbenchIfNeeded(on window: NSWindow) {
        if window.styleMask.contains(.fullScreen) {
            if window.toolbar?.isVisible != false {
                window.toolbar?.isVisible = false
            }
            return
        }
        if window.toolbarStyle != .unified {
            window.toolbarStyle = .unified
        }
        if window.toolbar?.isVisible != true {
            window.toolbar?.isVisible = true
        }
        if !isWorkbenchAppearanceHealthy(window) {
            applyWorkbenchAppearance(to: window)
        }
    }

    private static func applyWorkbenchAppearance(to window: NSWindow, forceToolbarVisible: Bool = false) {
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.remove(.fullScreenDisallowsTiling)
        window.collectionBehavior.insert(.fullScreenPrimary)

        window.styleMask.insert(.titled)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.fullSizeContentView)

        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.titlebarSeparatorStyle != .none {
            window.titlebarSeparatorStyle = .none
        }
        window.isMovableByWindowBackground = false
        if !window.isOpaque {
            window.isOpaque = true
        }
        if window.backgroundColor != NSColor.windowBackgroundColor {
            window.backgroundColor = NSColor.windowBackgroundColor
        }

        ensureUnifiedToolbar(on: window)
        if window.styleMask.contains(.fullScreen) {
            window.toolbar?.isVisible = false
        } else {
            unhideTrafficLights(on: window)
        }
    }

    private static func ensureUnifiedToolbar(on window: NSWindow, forceToolbarVisible: Bool = false) {
        window.toolbarStyle = .unified
        window.showsToolbarButton = false
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: NSToolbar.Identifier("AeroTerm.Workbench"))
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            window.toolbar = toolbar
        }
        if window.styleMask.contains(.fullScreen) {
            window.toolbar?.isVisible = false
        } else if forceToolbarVisible || !SessionManager.shared.isFullScreen {
            window.toolbar?.isVisible = true
        }
    }

    private static func isWorkbenchAppearanceHealthy(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled)
            && window.styleMask.contains(.resizable)
            && window.styleMask.contains(.fullSizeContentView)
            && window.titlebarAppearsTransparent
            && window.titleVisibility == .hidden
            && window.toolbarStyle == .unified
            && window.toolbar != nil
            && window.standardWindowButton(.closeButton)?.isHidden == false
            && window.standardWindowButton(.closeButton)?.superview?.isHidden == false
    }

    private static func unhideTrafficLights(on window: NSWindow) {
        for button in [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ] {
            button?.isHidden = false
            button?.alphaValue = 1
        }

        var node: NSView? = window.standardWindowButton(.closeButton)?.superview
        while let current = node {
            current.isHidden = false
            current.alphaValue = 1
            node = current.superview
        }
    }

    private static func revealTitlebarViews(in window: NSWindow) {
        guard let root = window.contentView?.superview else { return }
        setTitlebarViews(in: root, hidden: false)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
    }

    /// Splash → workbench 只放大一次。之后完全交给用户拖动，不再拉回默认尺寸。
    private static func applyInitialWorkbenchSizeIfNeeded(_ window: NSWindow) {
        guard !didApplyInitialWorkbenchSize else { return }
        didApplyInitialWorkbenchSize = true
        let current = window.contentView?.frame.size ?? window.frame.size
        let stillLaunchSize = matches(current, AppWindowLayout.splashSize)
            || matches(current, AppWindowLayout.wizardSize)
        guard stillLaunchSize else { return }
        window.setContentSize(AppWindowLayout.workbenchSize)
        window.center()
    }

    private static func matches(_ size: NSSize, _ target: NSSize) -> Bool {
        abs(size.width - target.width) < 8 && abs(size.height - target.height) < 8
    }

    // MARK: - Hide system titlebar (splash)

    private static func hideSystemTitlebar(on window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.showsToolbarButton = false

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.isHidden = true
            titlebarView.alphaValue = 0
            titlebarView.superview?.isHidden = true
            titlebarView.superview?.alphaValue = 0
        }
        if let root = window.contentView?.superview {
            setTitlebarViews(in: root, hidden: true)
        }
    }

    private static func setTitlebarViews(in root: NSView, hidden: Bool) {
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            let name = String(describing: type(of: view))
            if name.contains("Titlebar") {
                view.isHidden = hidden
                view.alphaValue = hidden ? 0 : 1
            }
            stack.append(contentsOf: view.subviews)
        }
    }

    private static func lockFixed(_ window: NSWindow, size: NSSize) {
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenDisallowsTiling)

        window.styleMask.remove(.resizable)
        window.styleMask.remove(.miniaturizable)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.titled)
        window.styleMask.insert(.fullSizeContentView)

        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.isOpaque = false
        window.contentView?.layer?.backgroundColor = CGColor.clear

        window.minSize = size
        window.maxSize = size
        window.setContentSize(size)
        window.isMovableByWindowBackground = true
    }
}
