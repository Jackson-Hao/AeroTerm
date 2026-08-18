import SwiftUI

public struct WorkspaceView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var settings = SettingsManager.shared

    public var body: some View {
        ZStack {
            if let activeSession = sessionManager.activeSession {
                sessionContentView(for: activeSession)
                    .id(activeSession.id)
                    .transition(.opacity)
            } else {
                WelcomeHomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: sessionManager.activeSessionID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func sessionContentView(for session: SessionItem) -> some View {
        switch session.type {
        case .tcpClient, .tcpServer:
            TCPToolView(session: session)
        case .udpTool:
            UDPToolView(session: session)
        case .serial:
            SerialToolView(session: session)
        case .telnet:
            TelnetToolView(session: session)
        case .httpClient:
            HTTPToolView(session: session)
        case .agentCLI:
            AgentCLIToolView(session: session)
        case .ssh, .sftp, .vnc, .rdp:
            WelcomeHomeView()
        }
    }
}
