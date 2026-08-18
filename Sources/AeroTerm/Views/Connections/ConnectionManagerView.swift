import SwiftUI
import AppKit

public struct ConnectionManagerView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @State private var selectedID: UUID?
    @State private var editorToken = UUID()

    public init(initialSelection: UUID? = nil) {
        _selectedID = State(initialValue: initialSelection)
    }

    public var body: some View {
        GeometryReader { geo in
            HSplitView {
                connectionList
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                    .frame(height: geo.size.height)

                Group {
                    if let selectedID, let config = sessionManager.savedConnections.first(where: { $0.id == selectedID }) {
                        ScrollView {
                            ConnectionEditorView(config: config)
                                .padding(20)
                        }
                        .id(editorToken)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary.opacity(0.45))
                            Text(loc.text("connection_empty"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360)
                .frame(height: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedID == nil {
                selectedID = sessionManager.savedConnections.first?.id
            }
        }
        .onChange(of: sessionManager.savedConnections.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = ids.first
                editorToken = UUID()
            }
        }
    }

    private var connectionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.text("connection_manager_title"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    if let selectedID {
                        sessionManager.requestDeleteConnection(id: selectedID)
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)
                .help(loc.text("delete_config"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if sessionManager.savedConnections.isEmpty {
                VStack {
                    Spacer()
                    Text(loc.text("connection_empty"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(sessionManager.savedConnections) { config in
                        HStack(spacing: 8) {
                            Image(systemName: config.type.iconName)
                                .font(.system(size: 11))
                                .foregroundColor(config.type.tintColor)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(subtitle(config))
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(Optional(config.id))
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.sidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: selectedID) { _, _ in
                    editorToken = UUID()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func subtitle(_ config: ConnectionConfig) -> String {
        if config.type == .serial {
            return "\(config.port) bps"
        }
        if config.type == .agentCLI {
            return config.host
        }
        let user = sessionManager.resolvedUsername(for: config)
        if config.type.usesAccountAuth && !user.isEmpty {
            return "\(user)@\(config.host):\(config.port)"
        }
        return "\(config.host):\(config.port)"
    }
}

public struct ConnectionManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var loc = LocalizationManager.shared
    let initialSelection: UUID?

    public init(initialSelection: UUID? = nil) {
        self.initialSelection = initialSelection
    }

    public var body: some View {
        VStack(spacing: 0) {
            ConnectionManagerView(initialSelection: initialSelection)
            Divider()
            HStack {
                Spacer()
                Button(loc.text("close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 720, height: 480)
    }
}
