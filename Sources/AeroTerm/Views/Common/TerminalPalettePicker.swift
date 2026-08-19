import SwiftUI

struct TerminalPalettePicker: View {
    @Binding var paletteID: String
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Picker(loc.text("serial_palette_label"), selection: $paletteID) {
            ForEach(SerialColorScheme.all) { scheme in
                Text(loc.text(scheme.nameKey)).tag(scheme.id)
            }
        }
        .labelsHidden()
    }
}

struct TerminalSessionChrome: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Text(loc.text("serial_palette_label"))
                .font(.system(size: 11, weight: .semibold))
            TerminalPalettePicker(paletteID: $settings.terminalPaletteID)
                .frame(maxWidth: 200)
            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
