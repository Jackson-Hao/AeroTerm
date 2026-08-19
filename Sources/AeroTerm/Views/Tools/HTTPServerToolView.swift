import SwiftUI

public struct HTTPServerToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        HTTPServerWorkbench(session: session, engine: resolved)
    }

    private var resolved: HTTPServerEngine {
        if let engine = sessionManager.httpServers[session.id] {
            return engine
        }
        let engine = HTTPServerEngine()
        sessionManager.httpServers[session.id] = engine
        return engine
    }
}

private struct HTTPServerWorkbench: View {
    let session: SessionItem
    @ObservedObject var engine: HTTPServerEngine
    @ObservedObject var loc = LocalizationManager.shared
    @State private var splitRatio = 0.58
    @State private var portText: String

    init(session: SessionItem, engine: HTTPServerEngine) {
        self.session = session
        self.engine = engine
        _portText = State(initialValue: String(session.port))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            VerticalSplit(ratio: $splitRatio) {
                logPane
            } bottom: {
                responsePane
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: engine.isRunning) { _, running in
            if running {
                SessionManager.shared.markSessionConnected(id: session.id)
            } else {
                SessionManager.shared.markSessionDisconnected(id: session.id)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.isRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(loc.text("http_server_title"))
                .font(.system(size: 11, weight: .semibold))
            Text(loc.text("port_label"))
                .foregroundStyle(.secondary)
            TextField("8080", text: $portText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 64)
                .disabled(engine.isRunning)
            Picker(loc.text("http_server_mode"), selection: $engine.mode) {
                ForEach(HTTPServerMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .frame(width: 120)
            Spacer()
            Text(String(format: loc.text("http_request_count"), engine.requestCount))
                .foregroundStyle(.secondary)
            Button(loc.text("tcp_clear")) { engine.clearLogs() }
            Button(engine.isRunning ? loc.text("tcp_disconnect") : loc.text("tcp_connect")) {
                toggle()
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? .red : .accentColor)
        }
        .font(.system(size: 11))
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var logPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.text("http_requests"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if engine.logs.isEmpty {
                            Text(loc.text("http_server_ready"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            ForEach(engine.logs) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("[\(TCPIO.stamp(item.timestamp))]")
                                            .foregroundStyle(.secondary)
                                        Text(item.direction.rawValue)
                                            .fontWeight(.bold)
                                            .foregroundStyle(item.direction.color)
                                    }
                                    Text(item.content)
                                        .textSelection(.enabled)
                                }
                                .font(.system(size: 11.5, design: .monospaced))
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

    private var responsePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.text("http_server_response"))
                .font(.system(size: 11, weight: .semibold))
            if engine.mode == .custom {
                HStack {
                    Text(loc.text("http_status"))
                    TextField("200", value: $engine.statusCode, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text(loc.text("http_content_type"))
                    TextField("application/json", text: $engine.contentType)
                        .textFieldStyle(.roundedBorder)
                }
                TextEditor(text: $engine.responseBody)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
            } else {
                Text(loc.text("http_echo_hint"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(10)
    }

    private func toggle() {
        if engine.isRunning {
            engine.stop()
            return
        }
        let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? session.port
        guard (1...65535).contains(port) else { return }
        SessionManager.shared.updateSessionEndpoint(id: session.id, host: session.host, port: port)
        engine.start(port: port)
    }
}
