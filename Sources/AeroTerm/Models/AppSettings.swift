import Foundation
import SwiftUI
import CoreText
import Combine

public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    public var id: String { rawValue }

    public var displayNameKey: String {
        switch self {
        case .system: return "theme_system"
        case .dark: return "theme_dark"
        case .light: return "theme_light"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        }
    }
}

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    @Published public var theme: AppTheme = .dark {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "AeroTerm.AppTheme.v2")
        }
    }

    @Published public var terminalFontSize: Double = 13.0 {
        didSet {
            UserDefaults.standard.set(terminalFontSize, forKey: "AeroTerm.TerminalFontSize.v2")
        }
    }

    // 默认终端字体：彻底锁定为 Cascadia Code NF
    @Published public var terminalFontName: String = "CascadiaCodeNF-Regular" {
        didSet {
            UserDefaults.standard.set(terminalFontName, forKey: "AeroTerm.TerminalFontName.v2")
        }
    }

    @Published public var showWelcomeOnLaunch: Bool = true {
        didSet {
            UserDefaults.standard.set(showWelcomeOnLaunch, forKey: "AeroTerm.ShowWelcomeOnLaunch.v2")
        }
    }

    @Published public var isShowingSettingsSheet: Bool = false

    private init() {
        registerCustomFonts()

        // 迁移并锁定主题
        if let savedTheme = UserDefaults.standard.string(forKey: "AeroTerm.AppTheme.v2"),
           let t = AppTheme(rawValue: savedTheme) {
            self.theme = t
        } else {
            self.theme = .dark
        }

        let savedFontSize = UserDefaults.standard.double(forKey: "AeroTerm.TerminalFontSize.v2")
        if savedFontSize >= 10 && savedFontSize <= 24 {
            self.terminalFontSize = savedFontSize
        } else {
            self.terminalFontSize = 13.0
        }

        // 强力迁移：如果之前是 SF Mono 或空，自动迁移为 CascadiaCodeNF-Regular
        let savedFontName = UserDefaults.standard.string(forKey: "AeroTerm.TerminalFontName.v2")
        if let font = savedFontName, !font.isEmpty, font != "SF Mono" {
            self.terminalFontName = font
        } else {
            self.terminalFontName = "CascadiaCodeNF-Regular"
            UserDefaults.standard.set("CascadiaCodeNF-Regular", forKey: "AeroTerm.TerminalFontName.v2")
        }

        if UserDefaults.standard.object(forKey: "AeroTerm.ShowWelcomeOnLaunch.v2") != nil {
            self.showWelcomeOnLaunch = UserDefaults.standard.bool(forKey: "AeroTerm.ShowWelcomeOnLaunch.v2")
        } else {
            self.showWelcomeOnLaunch = true
        }
    }

    private func registerCustomFonts() {
        let fontNames = [
            "CascadiaCodeNF-Regular.otf",
            "CascadiaCodeNF-Bold.otf",
            "CascadiaCodeNF-Italic.otf",
            "CascadiaCodeNF-BoldItalic.otf"
        ]
        
        let bundle = Bundle.module
        for fontName in fontNames {
            if let fontURL = bundle.url(forResource: fontName, withExtension: nil, subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            } else if let fontURL = Bundle.main.url(forResource: fontName, withExtension: nil) {
                CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            }
        }
    }
}

extension View {
    public func terminalFont(size: Double? = nil) -> some View {
        let name = SettingsManager.shared.terminalFontName
        let s = size ?? SettingsManager.shared.terminalFontSize
        return self.font(.custom(name, size: CGFloat(s)))
    }
}
