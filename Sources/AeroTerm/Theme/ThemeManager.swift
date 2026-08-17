import Foundation
import SwiftUI
import Combine

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    public let availableThemes: [ThemeConfig] = [
        AeroDarkTheme.config,
        AeroLightTheme.config
    ]

    @Published public var currentTheme: ThemeConfig {
        didSet {
            UserDefaults.standard.set(currentTheme.id, forKey: "AeroTerm.CurrentThemeID")
        }
    }

    private init() {
        let savedID = UserDefaults.standard.string(forKey: "AeroTerm.CurrentThemeID") ?? "aero-dark"
        if let theme = [AeroDarkTheme.config, AeroLightTheme.config].first(where: { $0.id == savedID }) {
            self.currentTheme = theme
        } else {
            self.currentTheme = AeroDarkTheme.config
        }
    }

    public func selectTheme(byID id: String) {
        if let target = availableThemes.first(where: { $0.id == id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.currentTheme = target
                if target.isDark {
                    SettingsManager.shared.theme = .dark
                } else {
                    SettingsManager.shared.theme = .light
                }
            }
        }
    }
}
