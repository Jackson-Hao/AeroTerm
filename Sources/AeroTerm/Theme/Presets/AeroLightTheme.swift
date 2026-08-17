import Foundation

public enum AeroLightTheme {
    public static let config = ThemeConfig(
        id: "aero-light",
        name: "Aero Light (Solar Mist)",
        isDark: false,
        backgroundColor: "#F8FAFC",
        surfaceColor: "#FFFFFF",
        sidebarColor: "#F1F5F9",
        textPrimaryColor: "#0F172A",
        textSecondaryColor: "#64748B",
        accentColor: "#0284C7",
        cursorColor: "#0284C7",
        palette: TerminalPalette(
            black: "#1E293B",
            red: "#DC2626",
            green: "#16A34A",
            yellow: "#D97706",
            blue: "#2563EB",
            magenta: "#9333EA",
            cyan: "#0891B2",
            white: "#F8FAFC"
        )
    )
}
