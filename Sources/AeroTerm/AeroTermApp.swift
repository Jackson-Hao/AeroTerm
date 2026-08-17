import SwiftUI

@main
struct AeroTermApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var loc = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(sessionManager)
                .environmentObject(settingsManager)
                .environmentObject(themeManager)
                .environmentObject(loc)
                .preferredColorScheme(settingsManager.theme.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(loc.text("settings_title") + "...") {
                    settingsManager.isShowingSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button(loc.text("new_connection_btn") + "...") {
                    sessionManager.isShowingStartupSplash = false
                    sessionManager.isShowingNewConnectionWizard = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button(loc.text("close_session")) {
                    if let id = sessionManager.activeSessionID {
                        sessionManager.closeSession(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(sessionManager.activeSessionID == nil)
            }

            CommandGroup(after: .windowArrangement) {
                Button(loc.text("welcome_window_title")) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sessionManager.isShowingStartupSplash = true
                    }
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            }
        }
    }
}
