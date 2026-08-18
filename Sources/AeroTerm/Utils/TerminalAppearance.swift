import AppKit
import SwiftUI
import SwiftTerm

@MainActor
enum TerminalAppearance {
    static var signature: String {
        let theme = ThemeManager.shared.currentTheme
        let settings = SettingsManager.shared
        return "\(theme.id)|\(settings.terminalFontName)|\(settings.terminalFontSize)"
    }

    static var backgroundColor: NSColor {
        NSColor(ThemeManager.shared.currentTheme.bg)
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
        let theme = ThemeManager.shared.currentTheme
        terminalView.focusRingType = .none
        terminalView.disableFullRedrawOnAnyChanges = true
        terminalView.nativeBackgroundColor = NSColor(theme.bg)
        terminalView.nativeForegroundColor = NSColor(theme.textPrimary)
        terminalView.caretColor = NSColor(theme.accent)
        terminalView.font = resolvedFont()
        return true
    }

    static func paintContainer(_ container: NSView) {
        container.wantsLayer = true
        container.layer?.backgroundColor = backgroundColor.cgColor
    }
}
