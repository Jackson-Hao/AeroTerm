import SwiftUI
import AppKit

public struct SSHToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        if let runtime = sessionManager.sshSessions[session.id] {
            SSHTerminalAttachView(runtime: runtime)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("SSH session is not connected.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.autoresizingMask = [.width, .height]
        container.focusRingType = .none
        container.wantsLayer = true
        container.clipsToBounds = true
        runtime.attach(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        runtime.applyTheme()
        runtime.attach(to: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.runtime.detach(from: nsView)
    }

    final class Coordinator {
        let runtime: SSHTerminalSession
        init(runtime: SSHTerminalSession) {
            self.runtime = runtime
        }
    }
}
