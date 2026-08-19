import SwiftUI

public struct DesktopDisplaySettingsForm: View {
    @Binding var settings: DesktopDisplaySettings
    var compact: Bool = false

    @ObservedObject private var loc = LocalizationManager.shared

    public init(settings: Binding<DesktopDisplaySettings>, compact: Bool = false) {
        _settings = settings
        self.compact = compact
    }

    public var body: some View {
        if compact {
            HStack(spacing: 10) {
                compactPicker(
                    title: loc.text("desktop_quality"),
                    selection: $settings.quality
                ) {
                    ForEach(DesktopQuality.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                compactPicker(
                    title: loc.text("desktop_refresh"),
                    selection: $settings.refreshRate
                ) {
                    ForEach(DesktopRefreshRate.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                labeledPicker(loc.text("desktop_quality"), selection: $settings.quality) {
                    ForEach(DesktopQuality.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                labeledPicker(loc.text("desktop_refresh"), selection: $settings.refreshRate) {
                    ForEach(DesktopRefreshRate.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
        }
    }

    private func labeledPicker<Value: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private func compactPicker<Value: Hashable, Content: View>(
        title: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(minWidth: 168)
        }
    }
}

struct DesktopDisplayChrome: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    var body: some View {
        let binding = Binding<DesktopDisplaySettings>(
            get: {
                sessionManager.sessions.first(where: { $0.id == session.id })?.desktop ?? session.desktop
            },
            set: { sessionManager.updateDesktopDisplay(for: session.id, desktop: $0) }
        )
        DesktopDisplaySettingsForm(settings: binding, compact: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
    }
}
