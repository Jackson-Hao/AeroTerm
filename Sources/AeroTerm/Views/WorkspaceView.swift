import SwiftUI
import AppKit

public struct WorkspaceView: View {
    @ObservedObject var sessionManager = SessionManager.shared

    private var primary: WorkspaceSurface {
        sessionManager.primarySurface
    }

    private var keepAliveSessions: [SessionItem] {
        sessionManager.sessions.filter { sessionManager.needsOffscreenKeepAlive($0) }
    }

    public var body: some View {
        ZStack {
            if let layout = primary.layout {
                PaneTreeView(
                    node: layout,
                    surfaceID: primary.id,
                    showsHeaderWhenSingle: layout.sessionIDs.count > 1 || hasSplit(layout)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WelcomeHomeView()
                WorkspaceDropCatcher(surfaceID: primary.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            ForEach(keepAliveSessions) { session in
                SessionContentView(session: session)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .focusEffectDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(sessionManager.isFullScreen ? .container : [])
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func hasSplit(_ node: PaneNode) -> Bool {
        if case .split = node { return true }
        return false
    }
}
