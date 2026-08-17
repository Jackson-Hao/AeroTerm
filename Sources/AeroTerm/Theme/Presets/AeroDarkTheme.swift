import Foundation

public enum AeroDarkTheme {
    public static let config = ThemeConfig(
        id: "aero-dark",
        name: "Aero Dark (Midnight Neo)",
        isDark: true,
        backgroundColor: "#0B0D11",
        surfaceColor: "#13171F",
        sidebarColor: "#0E1117",
        textPrimaryColor: "#F1F5F9",
        textSecondaryColor: "#94A3B8",
        accentColor: "#38BDF8",
        cursorColor: "#38BDF8",
        palette: TerminalPalette(
            black: "#0F172A",
            red: "#F87171",
            green: "#4ADE80",
            yellow: "#FBBF24",
            blue: "#60A5FA",
            magenta: "#C084FC",
            cyan: "#38BDF8",
            white: "#F8FAFC"
        )
    )
}
