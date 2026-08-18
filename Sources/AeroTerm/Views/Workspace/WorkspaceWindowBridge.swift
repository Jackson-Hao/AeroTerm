import SwiftUI
import AppKit

struct WorkspaceWindowBridge: View {
    static let groupID = "workspace-surface"

    static func windowIdentifier(for surfaceID: UUID) -> String {
        "AeroTerm.Detached.\(surfaceID.uuidString)"
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject var sessionManager = SessionManager.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: sessionManager.windowCommands) { _, _ in
                processCommands()
            }
            .onAppear {
                processCommands()
            }
    }

    private func processCommands() {
        let batch = sessionManager.consumeWindowCommands()
        for command in batch {
            switch command {
            case .open(let id):
                openWindow(id: Self.groupID, value: id)
            case .close(let id):
                dismissWindow(id: Self.groupID, value: id)
            case .focus(let id):
                focusDetached(id)
            }
        }
    }

    private func focusDetached(_ surfaceID: UUID) {
        let identifier = Self.windowIdentifier(for: surfaceID)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == identifier }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        openWindow(id: Self.groupID, value: surfaceID)
    }
}
