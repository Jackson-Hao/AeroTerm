import SwiftUI
import AppKit

public struct MainView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    public var body: some View {
        Group {
            if sessionManager.isShowingStartupSplash {
                splashContent
            } else {
                workbenchContent
            }
        }
        .background {
            WindowAccessor { window in
                FullScreenWindowDelegate.attach(to: window)
                WindowChrome.sync(window)
            }
        }
        .overlay {
            connectionHUD
        }
        .sheet(isPresented: $settingsManager.isShowingSettingsSheet) {
            SettingsView()
        }
        .alert(
            loc.text("alert_title"),
            isPresented: Binding<Bool>(
                get: { sessionManager.alertMessage != nil },
                set: { if !$0 { sessionManager.alertMessage = nil } }
            ),
            actions: {
                Button(loc.text("ok"), role: .cancel) {
                    sessionManager.alertMessage = nil
                }
            },
            message: {
                Text(sessionManager.alertMessage ?? "")
            }
        )
        .confirmationDialog(
            sessionManager.pendingDestructiveTitle(using: loc),
            isPresented: Binding(
                get: { sessionManager.pendingDestructiveAction != nil },
                set: { if !$0 { sessionManager.cancelPendingDestructiveAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button(sessionManager.pendingDestructiveConfirmLabel(using: loc), role: .destructive) {
                sessionManager.confirmPendingDestructiveAction()
            }
            Button(loc.text("cancel"), role: .cancel) {
                sessionManager.cancelPendingDestructiveAction()
            }
        } message: {
            Text(sessionManager.pendingDestructiveMessage(using: loc))
        }
    }

    @ViewBuilder
    private var splashContent: some View {
        if sessionManager.isShowingNewConnectionWizard {
            NewConnectionWizardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        } else {
            XcodeStartupWindowView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
    }

    private var workbenchContent: some View {
        NavigationSplitView(columnVisibility: $sessionManager.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
                .modifier(HideAutomaticSidebarToggle())
        } detail: {
            WorkspaceView()
                .modifier(HideAutomaticSidebarToggle())
                .focusEffectDisabled()
        }
        .modifier(WorkbenchChrome())
    }

    @ViewBuilder
    private var connectionHUD: some View {
        if let hud = sessionManager.connectionHUD {
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                ConnectionHUDView(hud: hud) {
                    if hud.isFinished {
                        sessionManager.dismissConnectionHUD()
                    } else {
                        sessionManager.cancelRemoteConnect()
                    }
                }
            }
        }
    }
}

/// 主页面顶栏只放一个侧栏按钮，钉在红绿灯右侧。
private struct WorkbenchChrome: ViewModifier {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            sessionManager.toggleSidebar()
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .help(
                        sessionManager.isSidebarCollapsed
                            ? loc.text("show_sidebar")
                            : loc.text("hide_sidebar")
                    )
                }
            }
            .toolbar(removing: .sidebarToggle)
            .toolbar(sessionManager.isFullScreen ? .hidden : .automatic)
            .frame(
                minWidth: AppWindowLayout.workbenchMinSize.width,
                minHeight: AppWindowLayout.workbenchMinSize.height
            )
    }
}

private struct HideAutomaticSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar(removing: .sidebarToggle)
    }
}
