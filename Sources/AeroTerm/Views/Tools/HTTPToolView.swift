import SwiftUI

public struct HTTPToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        HTTPClientWorkbench(session: session, controller: resolved)
    }

    private var resolved: HTTPClientController {
        if let existing = sessionManager.httpClients[session.id] {
            return existing
        }
        let controller = HTTPClientController()
        if controller.url.isEmpty, !session.host.isEmpty {
            let port = session.port > 0 ? ":\(session.port)" : ""
            controller.url = "\(session.host)\(port)/"
        }
        sessionManager.httpClients[session.id] = controller
        return controller
    }
}

private struct HTTPClientWorkbench: View {
    let session: SessionItem
    @ObservedObject var controller: HTTPClientController
    @ObservedObject var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var splitRatio = 0.48
    @State private var requestTab = 0
    @State private var responseTab = 0
    @State private var prettyJSON = true
    @State private var wsText = ""

    private let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            VerticalSplit(ratio: $splitRatio) {
                requestPane
            } bottom: {
                responsePane
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var urlBar: some View {
        HStack(spacing: 8) {
            Picker(loc.text("http_scheme"), selection: $controller.scheme) {
                ForEach(HTTPScheme.allCases) { item in
                    Text(item.rawValue.uppercased()).tag(item)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 132, idealWidth: 140)

            if !controller.scheme.isWebSocket {
                Picker("", selection: $controller.method) {
                    ForEach(methods, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 100, idealWidth: 108)
            }

            TextField(urlPlaceholder, text: $controller.url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            if controller.scheme.isWebSocket {
                Button(controller.socket.isConnected ? loc.text("tcp_disconnect") : loc.text("tcp_connect")) {
                    toggleWebSocket()
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.socket.isConnected ? .red : .accentColor)
            } else {
                Button {
                    sendHTTP()
                } label: {
                    HStack(spacing: 5) {
                        if controller.http.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(loc.text("http_send"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.http.isLoading || controller.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 11))
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var urlPlaceholder: String {
        switch controller.scheme {
        case .http: return "127.0.0.1:8080/api"
        case .https: return "example.com/api"
        case .ws: return "127.0.0.1:8080/ws"
        case .wss: return "example.com/ws"
        }
    }

    private var requestPane: some View {
        VStack(spacing: 0) {
            Picker("", selection: $requestTab) {
                Text(loc.text("http_params")).tag(0)
                Text(loc.text("http_headers")).tag(1)
                Text(loc.text("http_body")).tag(2)
                Text(loc.text("http_auth")).tag(3)
            }
            .pickerStyle(.segmented)
            .padding(8)
            Divider()
            Group {
                switch requestTab {
                case 0:
                    pairEditor($controller.params, keyTitle: "Name", valueTitle: "Value")
                case 1:
                    pairEditor($controller.headers, keyTitle: "Header", valueTitle: "Value")
                case 2:
                    bodyEditor
                default:
                    authEditor
                }
            }
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(loc.text("http_body_type"), selection: $controller.bodyKind) {
                ForEach(HTTPBodyKind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            if controller.bodyKind == .none {
                Text(loc.text("http_body_none"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $controller.body)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    private var authEditor: some View {
        Form {
            Picker(loc.text("http_auth"), selection: $controller.auth) {
                ForEach(HTTPAuthKind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if controller.auth == .bearer {
                TextField("Token", text: $controller.bearer)
                    .textFieldStyle(.roundedBorder)
            }
            if controller.auth == .basic {
                TextField(loc.text("account_username_label"), text: $controller.basicUser)
                    .textFieldStyle(.roundedBorder)
                SecureField(loc.text("password_label"), text: $controller.basicPass)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
    }

    private var responsePane: some View {
        VStack(spacing: 0) {
            if controller.scheme.isWebSocket {
                websocketPane
            } else {
                httpResponsePane
            }
        }
    }

    private var httpResponsePane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.text("http_response"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let resp = controller.http.lastResponse {
                    Text(verbatim: HTTPStatus.label(resp.statusCode))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(resp.isSuccess ? Color.green : Color.red)
                        .help(HTTPStatus.label(resp.statusCode))
                    Text(String(format: "%.1f ms", resp.durationMs))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(HexUtils.formatByteCount(resp.byteCount))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Picker("", selection: $responseTab) {
                Text(loc.text("http_headers")).tag(0)
                Text(loc.text("http_body")).tag(1)
                Text(loc.text("http_data")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            Divider()
            if let error = controller.http.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let resp = controller.http.lastResponse {
                switch responseTab {
                case 0:
                    headerTable(resp.headers)
                case 1:
                    rawBodyView(resp.bodyText)
                default:
                    dataView(resp)
                }
            } else {
                Text(loc.text("http_ready"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var websocketPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.text("http_ws_log"))
                    .font(.system(size: 11, weight: .semibold))
                Circle()
                    .fill(controller.socket.isConnected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Spacer()
                Button(loc.text("tcp_clear")) { controller.socket.clearLogs() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(controller.socket.logs) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(TCPIO.stamp(item.timestamp))]")
                                    .foregroundStyle(.secondary)
                                Text(item.direction.rawValue)
                                    .fontWeight(.bold)
                                    .foregroundStyle(item.direction.color)
                                Text(item.content)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .id(item.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: controller.socket.logs.count) {
                    if let last = controller.socket.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            Divider()
            HStack {
                TextField(loc.text("http_ws_message"), text: $wsText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendWS() }
                Button(loc.text("send_btn"), action: sendWS)
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.socket.isConnected || wsText.isEmpty)
            }
            .padding(8)
        }
    }

    private func headerTable(_ headers: [HTTPHeaderItem]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(loc.text("http_header_name"))
                    .frame(width: 200, alignment: .leading)
                Text(loc.text("http_header_value"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            Divider()
            if headers.isEmpty {
                Text(loc.text("http_headers_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(headers) { item in
                            HStack(alignment: .top, spacing: 0) {
                                Text(item.name)
                                    .frame(width: 200, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                Text(item.value)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            Divider()
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    private func rawBodyView(_ text: String, highlightJSON: Bool = false) -> some View {
        ScrollView {
            Group {
                if highlightJSON {
                    Text(JSONHighlighter.attributed(text, scheme: colorScheme))
                } else {
                    Text(text)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func dataView(_ resp: HTTPResponseData) -> some View {
        VStack(spacing: 0) {
            HStack {
                if resp.jsonPretty != nil {
                    Toggle(loc.text("http_pretty_json"), isOn: $prettyJSON)
                        .toggleStyle(.checkbox)
                } else {
                    Text(loc.text("http_data_raw"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            rawBodyView(
                prettyJSON ? (resp.jsonPretty ?? resp.bodyText) : resp.bodyText,
                highlightJSON: resp.jsonPretty != nil
            )
        }
    }

    private func pairEditor(_ pairs: Binding<[HTTPPair]>, keyTitle: String, valueTitle: String) -> some View {
        VStack(spacing: 0) {
            ForEach(pairs) { $item in
                HStack(spacing: 6) {
                    Toggle("", isOn: $item.enabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    TextField(keyTitle, text: $item.key)
                        .textFieldStyle(.roundedBorder)
                    TextField(valueTitle, text: $item.value)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        pairs.wrappedValue.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
            Button {
                pairs.wrappedValue.append(HTTPPair())
            } label: {
                Label(loc.text("http_add_row"), systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(8)
            Spacer()
        }
    }

    private func composedURL() -> String {
        let raw = controller.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.contains("://") { return raw }
        return "\(controller.scheme.rawValue)://\(raw)"
    }

    private func sendHTTP() {
        controller.http.send(
            method: controller.method,
            urlString: composedURL(),
            params: controller.params,
            headers: controller.headers,
            auth: controller.auth,
            bearer: controller.bearer,
            basicUser: controller.basicUser,
            basicPass: controller.basicPass,
            bodyKind: controller.bodyKind,
            body: controller.body
        )
    }

    private func toggleWebSocket() {
        if controller.socket.isConnected {
            controller.socket.disconnect()
        } else {
            controller.socket.connect(urlString: composedURL())
        }
    }

    private func sendWS() {
        let text = wsText
        guard !text.isEmpty else { return }
        controller.socket.send(text)
        wsText = ""
    }
}
