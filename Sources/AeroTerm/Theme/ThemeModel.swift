import SwiftUI

public struct TerminalPalette: Codable, Equatable, Sendable {
    public var black: String
    public var red: String
    public var green: String
    public var yellow: String
    public var blue: String
    public var magenta: String
    public var cyan: String
    public var white: String

    public init(
        black: String,
        red: String,
        green: String,
        yellow: String,
        blue: String,
        magenta: String,
        cyan: String,
        white: String
    ) {
        self.black = black
        self.red = red
        self.green = green
        self.yellow = yellow
        self.blue = blue
        self.magenta = magenta
        self.cyan = cyan
        self.white = white
    }
}

public struct ThemeConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isDark: Bool
    public var backgroundColor: String
    public var surfaceColor: String
    public var sidebarColor: String
    public var textPrimaryColor: String
    public var textSecondaryColor: String
    public var accentColor: String
    public var cursorColor: String
    public var palette: TerminalPalette

    public init(
        id: String,
        name: String,
        isDark: Bool,
        backgroundColor: String,
        surfaceColor: String,
        sidebarColor: String,
        textPrimaryColor: String,
        textSecondaryColor: String,
        accentColor: String,
        cursorColor: String,
        palette: TerminalPalette
    ) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.backgroundColor = backgroundColor
        self.surfaceColor = surfaceColor
        self.sidebarColor = sidebarColor
        self.textPrimaryColor = textPrimaryColor
        self.textSecondaryColor = textSecondaryColor
        self.accentColor = accentColor
        self.cursorColor = cursorColor
        self.palette = palette
    }

    // 辅助色彩转换
    public var bg: Color { Color(hex: backgroundColor) }
    public var surface: Color { Color(hex: surfaceColor) }
    public var sidebar: Color { Color(hex: sidebarColor) }
    public var textPrimary: Color { Color(hex: textPrimaryColor) }
    public var textSecondary: Color { Color(hex: textSecondaryColor) }
    public var accent: Color { Color(hex: accentColor) }
    public var cursor: Color { Color(hex: cursorColor) }
    public var termGreen: Color { Color(hex: palette.green) }
    public var termCyan: Color { Color(hex: palette.cyan) }
    public var termYellow: Color { Color(hex: palette.yellow) }
    public var termRed: Color { Color(hex: palette.red) }
    public var termBlue: Color { Color(hex: palette.blue) }
}

extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
