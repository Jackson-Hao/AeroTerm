import SwiftUI

public struct AgentCLIToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        let sessionId = session.id
        SwiftTermContainerView(
            command: session.host,
            arguments: session.customCommand != nil && !session.customCommand!.isEmpty ? [session.customCommand!] : nil,
            workingDirectory: session.workingDirectory ?? session.targetDevice ?? "~",
            environmentVariables: session.environmentVariables,
            onProcessTerminated: {
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        SessionManager.shared.closeSession(id: sessionId)
                    }
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
