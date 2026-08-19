import SwiftUI

public struct ConnectionHUDView: View {
    @ObservedObject var hud: ConnectionHUDState
    var onClose: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(hud.didSucceed ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.16))
                        .frame(width: 28, height: 28)
                    if hud.isFinished && hud.didSucceed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                    } else if hud.isFinished {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(hud.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(hud.subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(hud.lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Self.stamp(line.time))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .leading)
                                Text(line.text)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(color(for: line.kind))
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: hud.lines.count) {
                    if let last = hud.lines.last {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if !hud.isFinished || !hud.didSucceed {
                Divider()
                HStack {
                    Spacer()
                    if hud.isFinished {
                        Button("Close") { onClose() }
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Button("Cancel") { onClose() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 440, height: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private func color(for kind: ConnectionLogKind) -> Color {
        switch kind {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
