import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct TCPToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        if session.type == .tcpServer {
            TCPServerWorkbench(session: session, engine: resolvedServer)
        } else {
            TCPClientWorkbench(session: session, engine: resolvedClient)
        }
    }

    private var resolvedClient: TCPClientEngine {
        if let engine = sessionManager.tcpClientEngines[session.id] {
            return engine
        }
        let engine = TCPClientEngine()
        sessionManager.tcpClientEngines[session.id] = engine
        return engine
    }

    private var resolvedServer: TCPServerEngine {
        if let engine = sessionManager.tcpServerEngines[session.id] {
            return engine
        }
        let engine = TCPServerEngine()
        sessionManager.tcpServerEngines[session.id] = engine
        return engine
    }
}

private struct TCPClientWorkbench: View {
    let session: SessionItem
    @ObservedObject var engine: TCPClientEngine

    var body: some View {
        TCPConsoleView(
            isServer: false,
            session: session,
            isActive: engine.isConnected,
            logs: engine.logs,
            txBytes: engine.txBytes,
            rxBytes: engine.rxBytes,
            clientEndpoints: [],
            selectedEndpoint: .constant(nil),
            autoEcho: .constant(false),
            receivePath: engine.receiveFileURL?.path,
            fileTransferLabel: engine.fileTransferLabel,
            errorMessage: engine.errorMessage,
            onToggle: { host, port, localPort in
                if engine.isConnected || engine.isConnecting {
                    engine.disconnect()
                } else {
                    SessionManager.shared.updateSessionEndpoint(
                        id: session.id,
                        host: host,
                        port: port,
                        localPort: localPort
                    )
                    engine.connect(host: host, port: port, localPort: localPort)
                }
            },
            onClear: { engine.clearLogs() },
            onSend: { engine.send($0) },
            onBroadcast: { engine.send($0) },
            onSendFile: { engine.sendFile($0) },
            onSetReceiveFile: { engine.setReceiveFile($0) }
        )
        .onChange(of: engine.isConnected) { _, connected in
            if connected {
                SessionManager.shared.markSessionConnected(id: session.id)
            } else if !engine.isConnecting {
                SessionManager.shared.markSessionDisconnected(id: session.id)
            }
        }
    }
}

private struct TCPServerWorkbench: View {
    let session: SessionItem
    @ObservedObject var engine: TCPServerEngine

    var body: some View {
        TCPConsoleView(
            isServer: true,
            session: session,
            isActive: engine.isRunning,
            logs: engine.logs,
            txBytes: engine.txBytes,
            rxBytes: engine.rxBytes,
            clientEndpoints: engine.clientEndpoints,
            selectedEndpoint: Binding(
                get: { engine.selectedEndpoint },
                set: { engine.selectedEndpoint = $0 }
            ),
            autoEcho: Binding(
                get: { engine.autoEcho },
                set: { engine.autoEcho = $0 }
            ),
            receivePath: engine.receiveFileURL?.path,
            fileTransferLabel: engine.fileTransferLabel,
            errorMessage: engine.errorMessage,
            onToggle: { host, port, _ in
                if engine.isRunning {
                    engine.stop()
                } else {
                    SessionManager.shared.updateSessionEndpoint(id: session.id, host: host, port: port)
                    engine.start(port: port)
                }
            },
            onClear: { engine.clearLogs() },
            onSend: { engine.send($0) },
            onBroadcast: { engine.broadcast($0) },
            onSendFile: { engine.sendFile($0) },
            onSetReceiveFile: { engine.setReceiveFile($0) }
        )
        .onChange(of: engine.isRunning) { _, running in
            if running {
                SessionManager.shared.markSessionConnected(id: session.id)
            } else {
                SessionManager.shared.markSessionDisconnected(id: session.id)
            }
        }
    }
}

private struct TCPConsoleView: View {
    let isServer: Bool
    let session: SessionItem
    let isActive: Bool
    let logs: [NetworkLogItem]
    let txBytes: Int
    let rxBytes: Int
    let clientEndpoints: [String]
    @Binding var selectedEndpoint: String?
    @Binding var autoEcho: Bool
    let receivePath: String?
    let fileTransferLabel: String?
    let errorMessage: String?
    let onToggle: (String, Int, Int) -> Void
    let onClear: () -> Void
    let onSend: (Data) -> Void
    let onBroadcast: (Data) -> Void
    let onSendFile: (URL) -> Void
    let onSetReceiveFile: (URL?) -> Void

    @ObservedObject var loc = LocalizationManager.shared
    @State private var splitRatio = 0.62
    @State private var sendText = "Hello AeroTerm"
    @State private var sendAsHex = false
    @State private var showHex = false
    @State private var showLineNumbers = true
    @State private var showTimestamp = true
    @State private var encoding: TCPTextEncoding = .utf8
    @State private var lineEnding: TCPLineEnding = .lf
    @State private var intervalEnabled = false
    @State private var intervalMsText = "1000"
    @State private var intervalTask: Task<Void, Never>?
    @State private var sendToAll = false
    @State private var hostText: String
    @State private var portText: String
    @State private var localPortText: String

    init(
        isServer: Bool,
        session: SessionItem,
        isActive: Bool,
        logs: [NetworkLogItem],
        txBytes: Int,
        rxBytes: Int,
        clientEndpoints: [String],
        selectedEndpoint: Binding<String?>,
        autoEcho: Binding<Bool>,
        receivePath: String?,
        fileTransferLabel: String?,
        errorMessage: String?,
        onToggle: @escaping (String, Int, Int) -> Void,
        onClear: @escaping () -> Void,
        onSend: @escaping (Data) -> Void,
        onBroadcast: @escaping (Data) -> Void,
        onSendFile: @escaping (URL) -> Void,
        onSetReceiveFile: @escaping (URL?) -> Void
    ) {
        self.isServer = isServer
        self.session = session
        self.isActive = isActive
        self.logs = logs
        self.txBytes = txBytes
        self.rxBytes = rxBytes
        self.clientEndpoints = clientEndpoints
        _selectedEndpoint = selectedEndpoint
        _autoEcho = autoEcho
        self.receivePath = receivePath
        self.fileTransferLabel = fileTransferLabel
        self.errorMessage = errorMessage
        self.onToggle = onToggle
        self.onClear = onClear
        self.onSend = onSend
        self.onBroadcast = onBroadcast
        self.onSendFile = onSendFile
        self.onSetReceiveFile = onSetReceiveFile
        _hostText = State(initialValue: session.host)
        _portText = State(initialValue: String(session.port))
        _localPortText = State(initialValue: session.localPort > 0 ? String(session.localPort) : "0")
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            VerticalSplit(ratio: $splitRatio) {
                receivePane
            } bottom: {
                sendPane
            }
            Divider()
            statusBar
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            intervalTask?.cancel()
        }
        .onChange(of: intervalEnabled) { _, enabled in
            if enabled {
                startInterval()
            } else {
                intervalTask?.cancel()
                intervalTask = nil
            }
        }
        .onChange(of: sendAsHex) { _, hex in
            convertSendText(toHex: hex)
        }
    }

    private var canSend: Bool {
        isActive && (!isServer || !clientEndpoints.isEmpty)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isServer ? loc.text("tcp_server_listening") : loc.text("tcp_client_target"))
                .font(.system(size: 11, weight: .semibold))
            if !isServer {
                TextField(loc.text("host_label"), text: $hostText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 140)
                    .disabled(isActive)
            }
            TextField(loc.text("port_label"), text: $portText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 64)
                .disabled(isActive)
            if !isServer {
                Text(loc.text("tcp_local_port"))
                    .foregroundStyle(.secondary)
                TextField(loc.text("tcp_local_port_placeholder"), text: $localPortText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 72)
                    .disabled(isActive)
            }

            if isServer {
                Picker(loc.text("tcp_client_picker"), selection: $selectedEndpoint) {
                    Text(loc.text("tcp_all_clients")).tag(Optional<String>.none)
                    ForEach(clientEndpoints, id: \.self) { item in
                        Text(item).tag(Optional(item))
                    }
                }
                .frame(maxWidth: 190)
                Toggle(loc.text("tcp_echo"), isOn: $autoEcho)
                    .toggleStyle(.checkbox)
            }

            Spacer()

            Picker(loc.text("tcp_encoding"), selection: $encoding) {
                ForEach(TCPTextEncoding.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .frame(width: 118)

            Toggle(loc.text("hex_mode"), isOn: $showHex)
                .toggleStyle(.checkbox)
            Toggle(loc.text("tcp_line_numbers"), isOn: $showLineNumbers)
                .toggleStyle(.checkbox)
            Toggle(loc.text("tcp_show_time"), isOn: $showTimestamp)
                .toggleStyle(.checkbox)

            Button(loc.text("tcp_clear"), action: onClear)
            Button(isActive ? loc.text("tcp_disconnect") : loc.text("tcp_connect")) {
                toggleLink()
            }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .red : .accentColor)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var receivePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(loc.text("tcp_receive"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let receivePath {
                    Text(receivePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button(loc.text("tcp_stop_save")) { onSetReceiveFile(nil) }
                } else {
                    Button(loc.text("tcp_save_receive")) { pickReceiveFile() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if logs.isEmpty {
                            Text(loc.text("tcp_ready_waiting"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            ForEach(Array(logs.enumerated()), id: \.element.id) { index, item in
                                receiveRow(index: index + 1, item: item)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: logs.count) {
                    if let last = logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private var sendPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(loc.text("tcp_send"))
                    .font(.system(size: 11, weight: .semibold))
                Toggle(loc.text("hex_mode"), isOn: $sendAsHex)
                    .toggleStyle(.checkbox)
                Picker(loc.text("tcp_line_ending"), selection: $lineEnding) {
                    ForEach(TCPLineEnding.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .frame(width: 90)
                .disabled(sendAsHex)
                Toggle(loc.text("tcp_interval"), isOn: $intervalEnabled)
                    .toggleStyle(.checkbox)
                Text(loc.text("tcp_interval_every"))
                    .foregroundStyle(.secondary)
                TextField("1000", text: $intervalMsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                Text(loc.text("tcp_interval_unit"))
                    .foregroundStyle(.secondary)
                if isServer {
                    Toggle(loc.text("tcp_broadcast"), isOn: $sendToAll)
                        .toggleStyle(.checkbox)
                }
                Spacer()
                Button(loc.text("tcp_send_file")) { pickSendFile() }
                    .disabled(!canSend)
                Button(loc.text("send_btn")) { performSend() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            TextEditor(text: $sendText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("TX \(HexUtils.formatByteCount(txBytes))")
            Text("RX \(HexUtils.formatByteCount(rxBytes))")
            if isServer {
                Text(String(format: loc.text("tcp_client_count"), clientEndpoints.count))
            }
            if let fileTransferLabel {
                Text(fileTransferLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func receiveRow(index: Int, item: NetworkLogItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if showLineNumbers {
                Text(String(format: "%4d", index))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            if showTimestamp {
                Text("[\(TCPIO.stamp(item.timestamp))]")
                    .foregroundStyle(.secondary)
            }
            Text(item.direction.rawValue)
                .fontWeight(.bold)
                .foregroundStyle(item.direction.color)
                .frame(width: 28, alignment: .leading)
            if isServer, let remote = item.remoteEndpoint {
                Text(remote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(displayBody(item))
                .foregroundStyle(bodyColor(item))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    private func displayBody(_ item: NetworkLogItem) -> String {
        if item.direction == .system || item.direction == .error {
            return item.content
        }
        if showHex {
            if let payload = item.payload {
                return HexUtils.dataToHexString(payload)
            }
            return item.hexRepresentation ?? item.content
        }
        if let payload = item.payload {
            return encoding.decode(payload)
        }
        return item.content
    }

    private func bodyColor(_ item: NetworkLogItem) -> Color {
        switch item.direction {
        case .send: return .blue
        case .receive: return Color(nsColor: .systemGreen)
        case .system: return .secondary
        case .error: return .red
        }
    }

    private func payloadToSend() -> Data? {
        if sendAsHex {
            return HexUtils.hexStringToData(sendText)
        }
        guard var data = encoding.encode(sendText) else { return nil }
        data.append(lineEnding.bytes)
        return data
    }

    private func performSend() {
        guard canSend, let data = payloadToSend(), !data.isEmpty else { return }
        if isServer, sendToAll {
            onBroadcast(data)
        } else {
            onSend(data)
        }
    }

    private func parsedPort() -> Int? {
        let value = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value, (1...65535).contains(value) else { return nil }
        return value
    }

    private func parsedIntervalMs() -> Int {
        max(Int(intervalMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1000, 20)
    }

    private func parsedLocalPort() -> Int {
        let value = Int(localPortText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard (0...65535).contains(value) else { return 0 }
        return value
    }

    private func toggleLink() {
        if isActive {
            onToggle(hostText, parsedPort() ?? session.port, parsedLocalPort())
            return
        }
        guard let port = parsedPort() else { return }
        let host = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        onToggle(host.isEmpty ? session.host : host, port, parsedLocalPort())
    }

    private func convertSendText(toHex: Bool) {
        let raw = sendText
        if toHex {
            if HexUtils.hexStringToData(raw) != nil { return }
            if let data = encoding.encode(raw) {
                sendText = HexUtils.dataToHexString(data)
            }
            return
        }
        guard let data = HexUtils.hexStringToData(raw) else { return }
        sendText = encoding.decode(data)
    }

    private func startInterval() {
        intervalTask?.cancel()
        intervalTask = Task { @MainActor in
            while !Task.isCancelled, intervalEnabled {
                performSend()
                try? await Task.sleep(for: .milliseconds(parsedIntervalMs()))
            }
        }
    }

    private func pickSendFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = loc.text("tcp_send_file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onSendFile(url)
    }

    private func pickReceiveFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "tcp-recv.bin"
        panel.prompt = loc.text("tcp_save_receive")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        onSetReceiveFile(url)
    }
}
