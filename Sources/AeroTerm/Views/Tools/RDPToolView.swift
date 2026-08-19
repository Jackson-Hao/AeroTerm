import SwiftUI
import AppKit

public struct RDPToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        if let runtime = sessionManager.rdpSessions[session.id], runtime.isAlive {
            VStack(spacing: 0) {
                DesktopDisplayChrome(session: session)
                RDPAttachView(runtime: runtime)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(sessionManager.rdpSessions[session.id]?.lastError
                     ?? LocalizationManager.shared.text("rdp_disconnected"))
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

private struct RDPAttachView: NSViewRepresentable {
    @ObservedObject var runtime: RDPDesktopSession

    func makeNSView(context: Context) -> RDPCanvasView {
        runtime.canvas
    }

    func updateNSView(_ nsView: RDPCanvasView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RDPCanvasView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        let size = CGSize(width: width, height: height)
        runtime.updateViewport(size: size, backingScale: RemoteDesktopGeometry.backingScale(for: nsView))
        return size
    }
}
