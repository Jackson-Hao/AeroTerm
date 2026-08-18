import SwiftUI
import AppKit

@main
struct AeroTermApp: App {
    @NSApplicationDelegateAdaptor(AeroTermAppDelegate.self) private var appDelegate
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var loc = LocalizationManager.shared

    init() {
        SessionManager.shared.unlockVault()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(sessionManager)
                .environmentObject(settingsManager)
                .environmentObject(themeManager)
                .environmentObject(loc)
                .preferredColorScheme(settingsManager.theme.colorScheme)
                .background(WorkspaceWindowBridge())
        }
        .defaultLaunchBehavior(sessionManager.isVaultReady ? .automatic : .suppressed)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(loc.text("settings_title") + "...") {
                    settingsManager.isShowingSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button(loc.text("new_connection_btn") + "...") {
                    sessionManager.isShowingNewConnectionWizard = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!sessionManager.isVaultReady)

                Divider()

                Button(loc.text("close_session")) {
                    if let id = sessionManager.activeSessionID {
                        sessionManager.requestCloseSession(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(sessionManager.activeSessionID == nil)
            }

            CommandGroup(after: .sidebar) {
                Button(sessionManager.isSidebarCollapsed
                       ? loc.text("show_sidebar")
                       : loc.text("hide_sidebar")) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sessionManager.toggleSidebar()
                    }
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(!sessionManager.isVaultReady || sessionManager.isShowingStartupSplash)
            }

            CommandGroup(after: .windowArrangement) {
                Button(loc.text("welcome_window_title")) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sessionManager.isShowingStartupSplash = true
                    }
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                .disabled(!sessionManager.isVaultReady)
            }
        }

        WindowGroup(id: WorkspaceWindowBridge.groupID, for: UUID.self) { $surfaceID in
            if let surfaceID {
                DetachedWorkspaceView(surfaceID: surfaceID)
                    .environmentObject(sessionManager)
                    .environmentObject(settingsManager)
                    .environmentObject(themeManager)
                    .environmentObject(loc)
                    .preferredColorScheme(settingsManager.theme.colorScheme)
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 820, height: 520)
    }
}

@MainActor
final class AeroTermAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if !SessionManager.shared.isVaultReady {
            SessionManager.shared.unlockVault()
        }
        if !SessionManager.shared.isVaultReady {
            for window in NSApp.windows {
                window.alphaValue = 0
                window.hasShadow = false
                window.orderOut(nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SessionManager.shared.isVaultReady else {
            for window in NSApp.windows {
                window.orderOut(nil)
            }
            let loc = LocalizationManager.shared
            let alert = NSAlert()
            alert.messageText = loc.text("vault_denied_title")
            alert.informativeText = loc.text("vault_denied_message")
            alert.alertStyle = .critical
            alert.addButton(withTitle: loc.text("vault_denied_quit"))
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
    }
}
