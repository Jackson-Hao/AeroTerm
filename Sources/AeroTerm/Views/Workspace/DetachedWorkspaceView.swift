import SwiftUI
import AppKit
import QuartzCore

public struct DetachedWorkspaceView: View {
    let surfaceID: UUID

    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isFullScreen = false

    private var surface: WorkspaceSurface? {
        sessionManager.surface(id: surfaceID)
    }

    private func refreshFullScreen() {
        let identifier = WorkspaceWindowBridge.windowIdentifier(for: surfaceID)
        isFullScreen = NSApp.windows.contains {
            $0.identifier?.rawValue == identifier && $0.styleMask.contains(.fullScreen)
        }
    }

    private var windowTitle: String {
        let titles = (surface?.sessionIDs ?? []).compactMap { id in
            sessionManager.sessions.first(where: { $0.id == id })?.title
        }
        if titles.isEmpty { return loc.text("app_title") }
        return titles.joined(separator: " · ")
    }

    public var body: some View {
        ZStack {
            if let surface, let layout = surface.layout {
                PaneTreeView(node: layout, surfaceID: surface.id, showsHeaderWhenSingle: true)
            } else {
                Color.clear
                    .onAppear {
                        dismissWindow(id: WorkspaceWindowBridge.groupID, value: surfaceID)
                    }
                WorkspaceDropCatcher(surfaceID: surfaceID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusEffectDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 560, minHeight: 360)
        .ignoresSafeArea(isFullScreen ? .container : [])
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sessionManager.mergeSurfaceToMain(surfaceID)
                } label: {
                    Image(systemName: "rectangle.badge.arrow.left")
                }
                .help(loc.text("session_merge_main"))
            }
        }
        .background {
            WindowAccessor { window in
                window.identifier = NSUserInterfaceItemIdentifier(WorkspaceWindowBridge.windowIdentifier(for: surfaceID))
                if window.title != windowTitle {
                    window.title = windowTitle
                }
                window.isRestorable = false
                DetachedWindowDelegate.attach(to: window, surfaceID: surfaceID)
                WindowChrome.applyDetached(to: window)
                let fullscreen = window.styleMask.contains(.fullScreen)
                if isFullScreen != fullscreen {
                    isFullScreen = fullscreen
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            refreshFullScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            refreshFullScreen()
        }
        .onAppear {
            sessionManager.focusedSurfaceID = surfaceID
            refreshFullScreen()
        }
        .onChange(of: sessionManager.surface(id: surfaceID)?.layout) { _, layout in
            if layout == nil {
                dismissWindow(id: WorkspaceWindowBridge.groupID, value: surfaceID)
            }
        }
    }
}

@MainActor
final class DetachedWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = DetachedWindowDelegate()
    private var surfaceByWindow: [ObjectIdentifier: UUID] = [:]

    static func attach(to window: NSWindow, surfaceID: UUID) {
        window.delegate = shared
        shared.surfaceByWindow[ObjectIdentifier(window)] = surfaceID
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let id = surfaceByWindow[ObjectIdentifier(sender)] {
            SessionManager.shared.handleDetachedWindowClose(id)
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = surfaceByWindow[ObjectIdentifier(window)]
        else { return }
        SessionManager.shared.focusedSurfaceID = id
        WindowChrome.applyDetached(to: window)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        WindowChrome.beginUserLiveResize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        WindowChrome.endUserLiveResize()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        (notification.object as? NSWindow)?.toolbar?.isVisible = false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.toolbar?.isVisible = false
        relayout(window)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        (notification.object as? NSWindow)?.toolbar?.isVisible = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.toolbar?.isVisible = true
        WindowChrome.applyDetached(to: window)
        relayout(window)
    }

    private func relayout(_ window: NSWindow) {
        WorkspaceTilingNSView.relayoutAll(in: window)
        DispatchQueue.main.async {
            WorkspaceTilingNSView.relayoutAll(in: window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            WorkspaceTilingNSView.relayoutAll(in: window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        surfaceByWindow[ObjectIdentifier(window)] = nil
    }
}
