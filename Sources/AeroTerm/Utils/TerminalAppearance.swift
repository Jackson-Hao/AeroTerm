import AppKit
import SwiftUI
import SwiftTerm

@MainActor
enum TerminalAppearance {
    static var activePalette: SerialColorScheme {
        SerialColorScheme.named(SettingsManager.shared.terminalPaletteID)
    }

    static var signature: String {
        let theme = ThemeManager.shared.currentTheme
        let settings = SettingsManager.shared
        return "\(theme.id)|\(settings.terminalPaletteID)|\(settings.terminalFontName)|\(settings.terminalFontSize)"
    }

    static var backgroundColor: NSColor {
        activePalette.resolvedBackground
    }

    static func resolvedFont() -> NSFont {
        let settings = SettingsManager.shared
        return NSFont(name: settings.terminalFontName, size: CGFloat(settings.terminalFontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(settings.terminalFontSize), weight: .regular)
    }

    @discardableResult
    static func apply(to terminalView: TerminalView, lastSignature: inout String) -> Bool {
        let next = signature
        guard next != lastSignature else { return false }
        lastSignature = next
        activePalette.apply(to: terminalView)
        return true
    }

    static func paintContainer(_ container: NSView) {
        activePalette.paint(container)
    }
}
