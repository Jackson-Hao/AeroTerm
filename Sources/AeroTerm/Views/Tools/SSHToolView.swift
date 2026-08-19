import SwiftUI
import AppKit

public struct SSHToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        if let runtime = sessionManager.sshSessions[session.id], runtime.isAlive {
            VStack(spacing: 0) {
                TerminalSessionChrome()
                SSHTerminalAttachView(runtime: runtime)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(LocalizationManager.shared.text("ssh_disconnected"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button(LocalizationManager.shared.text("ssh_reconnect")) {
                    sessionManager.reconnect(session)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SSHTerminalAttachView: NSViewRepresentable {
    @ObservedObject var runtime: SSHTerminalSession
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared

    func makeCoordinator() -> Coordinator {
        Coordinator(runtime: runtime)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView(frame: .zero)
        runtime.attach(to: host)
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        runtime.applyTheme()
        runtime.attach(to: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TerminalHostView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ nsView: TerminalHostView, coordinator: Coordinator) {
        coordinator.runtime.detach(from: nsView)
    }

    final class Coordinator {
        let runtime: SSHTerminalSession
        init(runtime: SSHTerminalSession) {
            self.runtime = runtime
        }
    }
}
