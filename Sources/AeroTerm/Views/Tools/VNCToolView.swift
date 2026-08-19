import SwiftUI
import AppKit

public struct VNCToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        if let runtime = sessionManager.vncSessions[session.id], runtime.isAlive {
            VStack(spacing: 0) {
                DesktopDisplayChrome(session: session)
                VNCAttachView(runtime: runtime)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(sessionManager.vncSessions[session.id]?.lastError
                     ?? LocalizationManager.shared.text("vnc_disconnected"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(LocalizationManager.shared.text("ssh_reconnect")) {
                    sessionManager.reconnect(session)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct VNCAttachView: NSViewRepresentable {
    @ObservedObject var runtime: VNCDesktopSession

    func makeNSView(context: Context) -> VNCHostView {
        runtime.container
    }

    func updateNSView(_ nsView: VNCHostView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: VNCHostView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        let size = CGSize(width: width, height: height)
        runtime.updateViewport(size: size)
        return size
    }
}
