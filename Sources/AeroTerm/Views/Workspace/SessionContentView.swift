import SwiftUI

public struct SessionContentView: View {
    let session: SessionItem

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
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
        case .httpServer:
            HTTPServerToolView(session: session)
        case .agentCLI:
            AgentCLIToolView(session: session)
        case .ssh:
            SSHToolView(session: session)
        case .sftp:
            SFTPToolView(session: session)
        case .vnc:
            VNCToolView(session: session)
        case .rdp:
            RDPToolView(session: session)
        }
    }
}
