import SwiftUI
import AppKit

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部胶囊 Tab 切换栏
            topTabBar
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            Group {
                if selectedTab == 2 {
                    AccountManagerView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case 0:
                                appearanceSection
                            case 1:
                                terminalSection
                            default:
                                aboutSection
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 底部操作栏
            HStack {
                Spacer()
                Button(loc.text("close")) {
                    settings.isShowingSettingsSheet = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .frame(width: 680, height: selectedTab == 2 ? 500 : 460)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var topTabBar: some View {
        HStack(spacing: 6) {
            tabButton(title: loc.text("tab_appearance"), icon: "paintbrush.fill", tag: 0)
            tabButton(title: loc.text("tab_terminal"), icon: "terminal.fill", tag: 1)
            tabButton(title: loc.text("tab_accounts"), icon: "person.crop.circle", tag: 2)
            tabButton(title: loc.text("tab_about"), icon: "info.circle.fill", tag: 3)
        }
        .padding(3)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
    }

    private func tabButton(title: String, icon: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(NSColor.selectedControlColor).opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 1. Appearance Section (预设主题选择)
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme Presets")
                .font(.system(size: 13, weight: .bold))

            VStack(spacing: 12) {
                ForEach(themeManager.availableThemes) { theme in
                    themePresetRow(theme: theme)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func themePresetRow(theme: ThemeConfig) -> some View {
        let isSelected = themeManager.currentTheme.id == theme.id

        return Button {
            themeManager.selectTheme(byID: theme.id)
        } label: {
            HStack(spacing: 12) {
                // 调色板预览方块
                HStack(spacing: 2) {
                    theme.bg.frame(width: 14, height: 28)
                    theme.termCyan.frame(width: 8, height: 28)
                    theme.termGreen.frame(width: 8, height: 28)
                    theme.termYellow.frame(width: 8, height: 28)
                    theme.termRed.frame(width: 8, height: 28)
                }
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundColor(.primary)
                    Text(theme.isDark ? "Midnight dark terminal palette" : "Clean high-contrast light palette")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Terminal Section (默认采用 Cascadia Code NF)
    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.text("tab_terminal"))
                .font(.system(size: 13, weight: .bold))

            VStack(spacing: 14) {
                HStack {
                    Label(loc.text("font_family_label"), systemImage: "textformat")
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: $settings.terminalFontName) {
                        Text("Cascadia Code NF (Default)").tag("CascadiaCodeNF-Regular")
                        Text("SF Mono (System)").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("Courier New").tag("Courier New")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                Divider()

                HStack {
                    Label(loc.text("serial_palette_label"), systemImage: "paintpalette")
                        .font(.system(size: 12.5))
                    Spacer()
                    TerminalPalettePicker(paletteID: $settings.terminalPaletteID)
                        .frame(width: 220)
                }

                Divider()

                HStack {
                    Label("\(loc.text("font_size_label")): \(Int(settings.terminalFontSize)) pt", systemImage: "textformat.size")
                        .font(.system(size: 12.5))
                    Spacer()
                    Slider(value: $settings.terminalFontSize, in: 10...20, step: 1)
                        .frame(width: 170)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )

            // Terminal Preview Box (使用当前主题和 Cascadia Code NF 渲染)
            VStack(alignment: .leading, spacing: 6) {
                Text("Terminal Output Preview (Nerd Font Supported)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text("󰊤 main ").foregroundColor(themeManager.currentTheme.termYellow)
                        Text("root@aeroterm").foregroundColor(themeManager.currentTheme.termGreen)
                        Text(":").foregroundColor(themeManager.currentTheme.textPrimary)
                        Text("~").foregroundColor(themeManager.currentTheme.termCyan)
                        Text(" 󰄬").foregroundColor(themeManager.currentTheme.termGreen)
                        Text(" # uptime").foregroundColor(themeManager.currentTheme.textPrimary)
                    }
                    Text(" 21:25:00 up 42 days,  load average: 0.05, 0.03, 0.01")
                        .foregroundColor(themeManager.currentTheme.textSecondary)
                }
                .font(.custom(settings.terminalFontName, size: CGFloat(settings.terminalFontSize)))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(themeManager.currentTheme.bg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 3. About Section
    private var aboutSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                if let img = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 68, height: 68)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 3) {
                    Text("AeroTerm")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Version alpha-0818")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(loc.text("about_desc"))
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }
}
