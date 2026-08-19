import SwiftUI
import AppKit
import UniformTypeIdentifiers

private func parsedBaudRate(_ text: String) -> Int {
    let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 115200
    return max(value, 1)
}

public struct SerialToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        if session.serial.mode == .shell {
            SerialShellWorkbench(session: session, engine: resolvedEngine)
        } else {
            SerialTesterWorkbench(session: session, engine: resolvedEngine)
        }
    }

    private var resolvedEngine: SerialEngine {
        if let engine = sessionManager.serialEngines[session.id] {
            return engine
        }
        let engine = SerialEngine()
        engine.selectedPortPath = session.host
        engine.baudRate = session.port
        engine.settings = session.serial
        sessionManager.serialEngines[session.id] = engine
        return engine
    }
}

// MARK: - Shell (MobaXterm-style terminal)

private struct SerialShellWorkbench: View {
    let session: SessionItem
    @ObservedObject var engine: SerialEngine
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared

    @State private var devicePath: String
    @State private var baudText: String
    @State private var highlightStyle: SerialHighlightStyle
    @State private var colorSchemeID: String

    init(session: SessionItem, engine: SerialEngine) {
        self.session = session
        self.engine = engine
        _devicePath = State(initialValue: session.host)
        _baudText = State(initialValue: String(session.port > 0 ? session.port : 115200))
        _highlightStyle = State(initialValue: session.serial.highlightStyle)
        _colorSchemeID = State(initialValue: session.serial.colorSchemeID)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let runtime = sessionManager.serialTerminals[session.id], runtime.isAlive {
                SerialTerminalAttachView(runtime: runtime)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                disconnectedPlaceholder
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: engine.isOpened) { _, opened in
            if opened {
                sessionManager.markSessionConnected(id: session.id)
            } else {
                sessionManager.markSessionDisconnected(id: session.id)
            }
        }
        .onChange(of: highlightStyle) { _, value in
            sessionManager.serialTerminals[session.id]?.updateAppearance(
                highlightStyle: value,
                colorSchemeID: colorSchemeID
            )
        }
        .onChange(of: colorSchemeID) { _, value in
            sessionManager.serialTerminals[session.id]?.updateAppearance(
                highlightStyle: highlightStyle,
                colorSchemeID: value
            )
        }
        .onAppear {
            ensureRuntime()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.isOpened ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(loc.text("serial_shell_title"))
                .font(.system(size: 11, weight: .semibold))

            TextField("/dev/cu.usbserial", text: $devicePath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(minWidth: 160, maxWidth: 240)
                .disabled(engine.isOpened)

            TextField(loc.text("serial_baud_placeholder"), text: $baudText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 88)
                .disabled(engine.isOpened)

            Text(verbatim: session.serial.detailLabel)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)

            Picker(loc.text("serial_highlight_label"), selection: $highlightStyle) {
                ForEach(SerialHighlightStyle.allCases) { style in
                    Text(loc.text(style.titleKey)).tag(style)
                }
            }
            .frame(maxWidth: 160)
            TerminalPalettePicker(paletteID: $colorSchemeID)
                .frame(maxWidth: 160)

            Spacer()

            if let error = engine.lastErrorMessage, !error.isEmpty, !engine.isOpened {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Button(loc.text("tcp_clear")) {
                sessionManager.serialTerminals[session.id]?.clearScreen()
            }
            Button(loc.text("serial_export")) {
                exportTerminal()
            }
            Button(engine.isOpened ? loc.text("tcp_disconnect") : loc.text("tcp_connect")) {
                togglePort()
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isOpened ? .red : .accentColor)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var disconnectedPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(loc.text("serial_shell_disconnected"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button(loc.text("tcp_connect")) {
                togglePort()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureRuntime() {
        if sessionManager.serialTerminals[session.id] == nil {
            let runtime = SerialTerminalSession(engine: engine, sessionID: session.id, settings: session.serial)
            sessionManager.serialTerminals[session.id] = runtime
            runtime.start()
        }
    }

    private func togglePort() {
        if engine.isOpened {
            engine.closePort()
            return
        }
        let path = devicePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let baud = parsedBaudRate(baudText)
        sessionManager.updateSerialEndpoint(id: session.id, host: path, port: baud)
        ensureRuntime()
        _ = engine.openPort(path: path, baud: baud, settings: session.serial)
    }

    private func exportTerminal() {
        let text = sessionManager.serialTerminals[session.id]?.exportedText() ?? ""
        SerialFileExport.save(
            text: text,
            suggestedName: SerialFileExport.suggestedName(devicePath: devicePath, title: session.title),
            prompt: loc.text("serial_export")
        )
    }
}

private struct SerialTerminalAttachView: NSViewRepresentable {
    @ObservedObject var runtime: SerialTerminalSession
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared

    func makeCoordinator() -> Coordinator {
        Coordinator(runtime: runtime)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView(frame: .zero)
        runtime.attach(to: host)
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        runtime.applyTheme()
        runtime.attach(to: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TerminalHostView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ nsView: TerminalHostView, coordinator: Coordinator) {
        coordinator.runtime.detach(from: nsView)
    }

    final class Coordinator {
        let runtime: SerialTerminalSession
        init(runtime: SerialTerminalSession) {
            self.runtime = runtime
        }
    }
}

// MARK: - Tester (TCP-style workbench)

private struct SerialTesterWorkbench: View {
    let session: SessionItem
    @ObservedObject var engine: SerialEngine
    @ObservedObject var loc = LocalizationManager.shared

    @State private var splitRatio = 0.62
    @State private var sendText = "AT"
    @State private var sendAsHex = false
    @State private var showHex = false
    @State private var showLineNumbers = true
    @State private var showTimestamp = true
    @State private var encoding: TCPTextEncoding = .utf8
    @State private var lineEnding: TCPLineEnding = .lf
    @State private var intervalEnabled = false
    @State private var intervalMsText = "1000"
    @State private var intervalTask: Task<Void, Never>?
    @State private var devicePath: String
    @State private var baudText: String
    @State private var availablePorts: [SerialPortInfo] = []

    init(session: SessionItem, engine: SerialEngine) {
        self.session = session
        self.engine = engine
        _devicePath = State(initialValue: session.host)
        _baudText = State(initialValue: String(session.port > 0 ? session.port : 115200))
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
        .onAppear {
            availablePorts = SerialEngine.getAvailablePorts()
            if devicePath.isEmpty, let first = availablePorts.first {
                devicePath = first.path
            }
        }
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
        .onChange(of: engine.isOpened) { _, opened in
            if opened {
                SessionManager.shared.markSessionConnected(id: session.id)
            } else {
                SessionManager.shared.markSessionDisconnected(id: session.id)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.isOpened ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(loc.text("serial_tester_title"))
                .font(.system(size: 11, weight: .semibold))

            if availablePorts.isEmpty {
                TextField("/dev/cu.usbserial", text: $devicePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 160, maxWidth: 240)
                    .disabled(engine.isOpened)
            } else {
                Picker("", selection: $devicePath) {
                    if !devicePath.isEmpty, !availablePorts.contains(where: { $0.path == devicePath }) {
                        Text(devicePath).tag(devicePath)
                    }
                    ForEach(availablePorts, id: \.path) { port in
                        Text(port.name).tag(port.path)
                    }
                }
                .frame(maxWidth: 180)
                .disabled(engine.isOpened)
            }

            TextField(loc.text("serial_baud_placeholder"), text: $baudText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 88)
                .disabled(engine.isOpened)

            Text(verbatim: session.serial.detailLabel)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)

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
            Button(engine.isOpened ? loc.text("tcp_disconnect") : loc.text("tcp_connect")) {
                togglePort()
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isOpened ? .red : .accentColor)
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
                Button(loc.text("serial_save_as")) { exportLogs() }
                    .disabled(engine.logs.isEmpty)
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
                            Text(loc.text("serial_ready_waiting"))
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
                    .disabled(!engine.isOpened)
                Button(loc.text("send_btn")) { performSend() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!engine.isOpened)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(loc.text("serial_send_shortcut"))
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
                .onKeyPress { press in
                    guard press.key == .return, press.modifiers.contains(.command) else { return .ignored }
                    performSend()
                    return .handled
                }
        }
        .onKeyPress { press in
            guard press.key == .return, press.modifiers.contains(.command) else { return .ignored }
            performSend()
            return .handled
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("TX \(HexUtils.formatByteCount(engine.txBytes))")
            Text("RX \(HexUtils.formatByteCount(engine.rxBytes))")
            Text(verbatim: shortDevice)
                .foregroundStyle(.secondary)
            if let fileTransferLabel = engine.fileTransferLabel {
                Text(fileTransferLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let errorMessage = engine.lastErrorMessage, !errorMessage.isEmpty {
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

    private var shortDevice: String {
        let path = devicePath.isEmpty ? session.host : devicePath
        return "\(path.replacingOccurrences(of: "/dev/cu.", with: "")) @ \(parsedBaudRate(baudText)) \(session.serial.lineSpec)"
    }

    private func receiveRow(index: Int, item: NetworkLogItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if showLineNumbers {
                Text(verbatim: String(format: "%4d", index))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            if showTimestamp {
                Text(verbatim: "[\(TCPIO.stamp(item.timestamp))]")
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: item.direction.rawValue)
                .fontWeight(.bold)
                .foregroundStyle(item.direction.color)
                .frame(width: 28, alignment: .leading)
            Text(verbatim: displayBody(item))
                .foregroundStyle(bodyColor(item))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    private func displayBody(_ item: NetworkLogItem) -> String {
        if item.direction == .system || item.direction == .error {
            return HexUtils.sanitizedText(item.content)
        }
        if showHex {
            if let payload = item.payload {
                return HexUtils.dataToHexString(payload)
            }
            return item.hexRepresentation ?? HexUtils.sanitizedText(item.content)
        }
        if let payload = item.payload {
            return SerialANSI.visibleText(payload, decode: encoding.decode)
        }
        return SerialANSI.stripResidues(HexUtils.sanitizedText(item.content))
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
        guard engine.isOpened, let data = payloadToSend(), !data.isEmpty else { return }
        engine.send(data: data)
    }

    private func parsedIntervalMs() -> Int {
        max(Int(intervalMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1000, 20)
    }

    private func togglePort() {
        if engine.isOpened {
            engine.closePort()
            return
        }
        let path = devicePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let baud = parsedBaudRate(baudText)
        SessionManager.shared.updateSerialEndpoint(id: session.id, host: path, port: baud)
        _ = engine.openPort(path: path, baud: baud, settings: session.serial)
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
        engine.sendFile(url)
    }

    private func pickReceiveFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = SerialFileExport.contentTypes
        panel.nameFieldStringValue = SerialFileExport.suggestedName(devicePath: devicePath, title: session.title) + "-rx"
        panel.prompt = loc.text("tcp_save_receive")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        engine.setReceiveFile(url)
    }

    private func exportLogs() {
        var lines: [String] = []
        lines.reserveCapacity(engine.logs.count)
        for item in engine.logs {
            lines.append("[\(TCPIO.stamp(item.timestamp))] \(item.direction.rawValue) \(displayBody(item))")
        }
        SerialFileExport.save(
            text: lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"),
            suggestedName: SerialFileExport.suggestedName(devicePath: devicePath, title: session.title),
            prompt: loc.text("serial_save_as")
        )
    }
}

@MainActor
enum SerialFileExport {
    static var contentTypes: [UTType] {
        let log = UTType(filenameExtension: "log") ?? .plainText
        return [log, .plainText]
    }

    static func suggestedName(devicePath: String, title: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd-HH:mm:ss"
        let stamp = formatter.string(from: Date())
        var name = devicePath.replacingOccurrences(of: "/dev/cu.", with: "")
            .replacingOccurrences(of: "/dev/", with: "")
        if name.isEmpty {
            name = title
        }
        name = name.replacingOccurrences(of: "/", with: "-")
        return "[\(stamp)]-\(name)"
    }

    static func save(text: String, suggestedName: String, prompt: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = contentTypes
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName
        panel.prompt = prompt
        panel.message = LocalizationManager.shared.text("serial_export_format_hint")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = ensuredTextURL(url)
        try? text.data(using: .utf8)?.write(to: target, options: .atomic)
    }

    private static func ensuredTextURL(_ url: URL) -> URL {
        let ext = url.pathExtension.lowercased()
        if ext == "log" || ext == "txt" { return url }
        return url.appendingPathExtension("txt")
    }
}
