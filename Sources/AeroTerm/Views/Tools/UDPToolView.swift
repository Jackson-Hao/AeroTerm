import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct UDPToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        UDPWorkbench(session: session, engine: resolvedEngine)
    }

    private var resolvedEngine: UDPEngine {
        if let engine = sessionManager.udpEngines[session.id] {
            return engine
        }
        let engine = UDPEngine()
        sessionManager.udpEngines[session.id] = engine
        return engine
    }
}

private struct UDPWorkbench: View {
    let session: SessionItem
    @ObservedObject var engine: UDPEngine
    @ObservedObject var loc = LocalizationManager.shared

    @State private var splitRatio = 0.62
    @State private var sendText = "Hello AeroTerm"
    @State private var sendAsHex = false
    @State private var showHex = false
    @State private var showLineNumbers = true
    @State private var showTimestamp = true
    @State private var encoding: TCPTextEncoding = .utf8
    @State private var lineEnding: TCPLineEnding = .none
    @State private var intervalEnabled = false
    @State private var intervalMsText = "1000"
    @State private var intervalTask: Task<Void, Never>?
    @State private var mode: UDPMode
    @State private var hostText: String
    @State private var portText: String
    @State private var localPortText: String

    init(session: SessionItem, engine: UDPEngine) {
        self.session = session
        self.engine = engine
        _mode = State(initialValue: session.udpMode)
        _hostText = State(initialValue: session.host)
        _portText = State(initialValue: String(session.port))
        _localPortText = State(initialValue: session.localPort > 0 ? String(session.localPort) : String(session.port))
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
        .onDisappear { intervalTask?.cancel() }
        .onChange(of: intervalEnabled) { _, enabled in
            if enabled { startInterval() } else { intervalTask?.cancel(); intervalTask = nil }
        }
        .onChange(of: sendAsHex) { _, hex in
            convertSendText(toHex: hex)
        }
        .onChange(of: engine.isListening) { _, listening in
            if listening {
                SessionManager.shared.markSessionConnected(id: session.id)
            } else {
                SessionManager.shared.markSessionDisconnected(id: session.id)
            }
        }
    }

    private var canSend: Bool { engine.isListening }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.isListening ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(loc.text("udp_title"))
                .font(.system(size: 11, weight: .semibold))
            Picker(loc.text("udp_mode"), selection: $mode) {
                ForEach(UDPMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .frame(width: 120)
            .disabled(engine.isListening)

            TextField(hostPlaceholder, text: $hostText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 130)
                .disabled(engine.isListening)

            Text(loc.text("port_label"))
                .foregroundStyle(.secondary)
            TextField("8080", text: $portText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60)
                .disabled(engine.isListening)

            Text(loc.text("tcp_local_port"))
                .foregroundStyle(.secondary)
            TextField(loc.text("tcp_local_port_placeholder"), text: $localPortText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 72)
                .disabled(engine.isListening)

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

            Button(loc.text("tcp_clear")) { engine.clearLogs() }
            Button(engine.isListening ? loc.text("tcp_disconnect") : loc.text("tcp_connect")) {
                toggleLink()
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isListening ? .red : .accentColor)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var hostPlaceholder: String {
        switch mode {
        case .unicast: return "127.0.0.1"
        case .multicast: return "239.255.0.1"
        case .broadcast: return "255.255.255.255"
        }
    }

    private var receivePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(loc.text("tcp_receive"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let path = engine.receiveFileURL?.path {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button(loc.text("tcp_stop_save")) { engine.setReceiveFile(nil) }
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
                        if engine.logs.isEmpty {
                            Text(loc.text("udp_ready_waiting"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            ForEach(Array(engine.logs.enumerated()), id: \.element.id) { index, item in
                                receiveRow(index: index + 1, item: item)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: engine.logs.count) {
                    if let last = engine.logs.last {
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
            Text(mode.title)
            Text("TX \(HexUtils.formatByteCount(engine.txBytes))")
            Text("RX \(HexUtils.formatByteCount(engine.rxBytes))")
            if let label = engine.fileTransferLabel {
                Text(label).foregroundStyle(.secondary)
            }
            Spacer()
            if let error = engine.errorMessage, !error.isEmpty {
                Text(error).foregroundStyle(.red).lineLimit(1)
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
            if let remote = item.remoteEndpoint {
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
        if item.direction == .system || item.direction == .error { return item.content }
        if showHex {
            if let payload = item.payload { return HexUtils.dataToHexString(payload) }
            return item.hexRepresentation ?? item.content
        }
        if let payload = item.payload { return encoding.decode(payload) }
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

    private func parsedPort(_ text: String, fallback: Int) -> Int? {
        let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
        guard (1...65535).contains(value) else { return nil }
        return value
    }

    private func toggleLink() {
        if engine.isListening {
            engine.stop()
            return
        }
        guard let targetPort = parsedPort(portText, fallback: session.port),
              let localPort = parsedPort(localPortText, fallback: session.localPort > 0 ? session.localPort : targetPort)
        else { return }
        var host = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            host = hostPlaceholder
            hostText = host
        }
        SessionManager.shared.updateSessionEndpoint(
            id: session.id,
            host: host,
            port: targetPort,
            localPort: localPort
        )
        SessionManager.shared.updateSessionUDPMode(id: session.id, mode: mode)
        engine.start(mode: mode, localPort: localPort, targetHost: host, targetPort: targetPort)
    }

    private func payloadToSend() -> Data? {
        if sendAsHex { return HexUtils.hexStringToData(sendText) }
        guard var data = encoding.encode(sendText) else { return nil }
        data.append(lineEnding.bytes)
        return data
    }

    private func performSend() {
        guard canSend, let data = payloadToSend(), !data.isEmpty else { return }
        engine.send(data)
    }

    private func startInterval() {
        intervalTask?.cancel()
        intervalTask = Task { @MainActor in
            while !Task.isCancelled, intervalEnabled {
                performSend()
                let millis = max(Int(intervalMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1000, 20)
                try? await Task.sleep(for: .milliseconds(millis))
            }
        }
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

    private func pickSendFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = loc.text("tcp_send_file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        engine.sendFile(url)
    }

    private func pickReceiveFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "udp-recv.bin"
        panel.prompt = loc.text("tcp_save_receive")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        engine.setReceiveFile(url)
    }
}
