import Foundation
import Combine
import Network

public enum HTTPScheme: String, CaseIterable, Identifiable, Sendable {
    case http, https, ws, wss
    public var id: String { rawValue }
    public var isWebSocket: Bool { self == .ws || self == .wss }
}

public enum HTTPBodyKind: String, CaseIterable, Identifiable, Sendable {
    case none, json, form, raw
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "None"
        case .json: return "JSON"
        case .form: return "Form"
        case .raw: return "Raw"
        }
    }
}

public enum HTTPStatus {
    public static func phrase(_ code: Int) -> String {
        switch code {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 102: return "Processing"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 418: return "I'm a teapot"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default:
            switch code {
            case 100..<200: return "Informational"
            case 200..<300: return "Success"
            case 300..<400: return "Redirect"
            case 400..<500: return "Client Error"
            case 500..<600: return "Server Error"
            default: return "Unknown"
            }
        }
    }

    public static func label(_ code: Int) -> String {
        "\(code): \(phrase(code))"
    }
}

public enum HTTPAuthKind: String, CaseIterable, Identifiable, Sendable {
    case none, bearer, basic
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "None"
        case .bearer: return "Bearer"
        case .basic: return "Basic"
        }
    }
}

public struct HTTPPair: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var enabled: Bool
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), enabled: Bool = true, key: String = "", value: String = "") {
        self.id = id
        self.enabled = enabled
        self.key = key
        self.value = value
    }
}

public struct HTTPHeaderItem: Identifiable, Sendable {
    public var id: String { name.lowercased() + ":" + value }
    public let name: String
    public let value: String
}

public struct HTTPResponseData: Sendable {
    public let statusCode: Int
    public let durationMs: Double
    public let headers: [HTTPHeaderItem]
    public let bodyText: String
    public let jsonPretty: String?
    public let byteCount: Int
    public let isSuccess: Bool

    public init(
        statusCode: Int,
        durationMs: Double,
        headers: [HTTPHeaderItem],
        bodyText: String,
        jsonPretty: String?,
        byteCount: Int,
        isSuccess: Bool
    ) {
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.headers = headers
        self.bodyText = bodyText
        self.jsonPretty = jsonPretty
        self.byteCount = byteCount
        self.isSuccess = isSuccess
    }
}

@MainActor
public final class HTTPEngine: ObservableObject {
    @Published public var isLoading = false
    @Published public var lastResponse: HTTPResponseData?
    @Published public var errorMessage: String?

    private var currentTask: URLSessionDataTask?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    public func send(
        method: String,
        urlString: String,
        params: [HTTPPair],
        headers: [HTTPPair],
        auth: HTTPAuthKind,
        bearer: String,
        basicUser: String,
        basicPass: String,
        bodyKind: HTTPBodyKind,
        body: String
    ) {
        cancel()
        errorMessage = nil
        lastResponse = nil

        guard var components = URLComponents(string: normalizedHTTPURL(urlString)) else {
            errorMessage = "Invalid URL"
            return
        }
        let query = params.filter { $0.enabled && !$0.key.isEmpty }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let url = components.url else {
            errorMessage = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        for pair in headers where pair.enabled && !pair.key.isEmpty {
            request.setValue(pair.value, forHTTPHeaderField: pair.key)
        }

        switch auth {
        case .none:
            break
        case .bearer:
            if !bearer.isEmpty {
                request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            let token = Data("\(basicUser):\(basicPass)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        if method != "GET", method != "HEAD" {
            switch bodyKind {
            case .none:
                break
            case .json:
                request.httpBody = body.data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                }
            case .form:
                let encoded = paramsToForm(headers)
                request.httpBody = formBody(from: body)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
                }
                _ = encoded
            case .raw:
                request.httpBody = body.data(using: .utf8)
            }
        }

        isLoading = true
        let start = CFAbsoluteTimeGetCurrent()
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    if (error as NSError).code != NSURLErrorCancelled {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.errorMessage = "Non-HTTP response"
                    return
                }
                let payload = data ?? Data()
                let parsed = Self.parseBody(payload)
                self.lastResponse = HTTPResponseData(
                    statusCode: http.statusCode,
                    durationMs: duration,
                    headers: http.allHeaderFields.compactMap { key, value in
                        let name = "\(key)"
                        guard !name.isEmpty else { return nil }
                        return HTTPHeaderItem(name: name, value: "\(value)")
                    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                    bodyText: parsed.raw,
                    jsonPretty: parsed.json,
                    byteCount: payload.count,
                    isSuccess: (200...299).contains(http.statusCode)
                )
            }
        }
        currentTask = task
        task.resume()
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }

    private func normalizedHTTPURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    private func formBody(from raw: String) -> Data? {
        if raw.contains("=") {
            return raw.data(using: .utf8)
        }
        return raw.data(using: .utf8)
    }

    private func paramsToForm(_ pairs: [HTTPPair]) -> String {
        pairs.filter { $0.enabled && !$0.key.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }

    private static func parseBody(_ data: Data) -> (raw: String, json: String?) {
        let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? "<binary \(data.count) bytes>"
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return (raw, text)
        }
        return (raw, nil)
    }
}

@MainActor
public final class WebSocketEngine: ObservableObject {
    @Published public var isConnected = false
    @Published public var isConnecting = false
    @Published public var errorMessage: String?
    @Published public var logs: [NetworkLogItem] = []

    private var task: URLSessionWebSocketTask?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config)
    }()

    public func connect(urlString: String) {
        disconnect()
        errorMessage = nil
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("http://") {
            raw = "ws://" + raw.dropFirst(7)
        } else if raw.lowercased().hasPrefix("https://") {
            raw = "wss://" + raw.dropFirst(8)
        } else if !raw.lowercased().hasPrefix("ws://"), !raw.lowercased().hasPrefix("wss://") {
            raw = "ws://" + raw
        }
        guard let url = URL(string: raw) else {
            errorMessage = "Invalid WebSocket URL"
            return
        }
        isConnecting = true
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        isConnected = true
        isConnecting = false
        append(.system, "Connected \(raw)")
        receiveLoop()
    }

    public func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if isConnected {
            append(.system, "Disconnected")
        }
        isConnected = false
        isConnecting = false
    }

    public func send(_ text: String) {
        guard isConnected, let task, !text.isEmpty else { return }
        task.send(.string(text)) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.append(.error, error.localizedDescription)
                } else {
                    self?.append(.send, text)
                }
            }
        }
    }

    public func clearLogs() {
        logs.removeAll()
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.append(.receive, text)
                    case .data(let data):
                        self.append(.receive, HexUtils.dataToHexString(data), payload: data)
                    @unknown default:
                        break
                    }
                    self.receiveLoop()
                case .failure(let error):
                    self.append(.error, error.localizedDescription)
                    self.isConnected = false
                    self.task = nil
                }
            }
        }
    }

    private func append(_ direction: LogDirection, _ text: String, payload: Data? = nil) {
        logs.append(
            NetworkLogItem(
                direction: direction,
                content: text,
                hexRepresentation: payload.map { HexUtils.dataToHexString($0) },
                byteCount: payload?.count ?? text.utf8.count,
                payload: payload
            )
        )
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }
}

@MainActor
public final class HTTPClientController: ObservableObject {
    @Published public var scheme: HTTPScheme = .http
    @Published public var method = "GET"
    @Published public var url = ""
    @Published public var params: [HTTPPair] = [HTTPPair()]
    @Published public var headers: [HTTPPair] = [
        HTTPPair(key: "Accept", value: "*/*")
    ]
    @Published public var bodyKind: HTTPBodyKind = .json
    @Published public var body = "{\n  \"message\": \"Hello from AeroTerm\"\n}"
    @Published public var auth: HTTPAuthKind = .none
    @Published public var bearer = ""
    @Published public var basicUser = ""
    @Published public var basicPass = ""

    public let http = HTTPEngine()
    public let socket = WebSocketEngine()
    private var bag = Set<AnyCancellable>()

    public init() {
        http.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &bag)
        socket.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &bag)
    }

    public func shutdown() {
        http.cancel()
        socket.disconnect()
    }
}

public enum HTTPServerMode: String, CaseIterable, Identifiable, Sendable {
    case echo
    case custom
    public var id: String { rawValue }
    public var title: String { self == .echo ? "Echo" : "Custom" }
}

public final class HTTPServerEngine: ObservableObject, @unchecked Sendable {
    @Published public var isRunning = false
    @Published public var errorMessage: String?
    @Published public var logs: [NetworkLogItem] = []
    @Published public var mode: HTTPServerMode = .echo
    @Published public var statusCode = 200
    @Published public var contentType = "application/json"
    @Published public var responseBody = "{\n  \"ok\": true\n}"
    @Published public var requestCount = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.aeroterm.httpserver", qos: .userInitiated)
    private var isDisposed = false
    private var epoch: UInt64 = 0

    public func start(port: Int) {
        epoch += 1
        let token = epoch
        stop(resetEpoch: false)
        errorMessage = nil
        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else {
            errorMessage = "Invalid port: \(port)"
            return
        }
        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self, !self.isDisposed, self.epoch == token else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.append(.system, "HTTP server listening on :\(port)")
                    case .failed(let error):
                        self.isRunning = false
                        self.errorMessage = error.localizedDescription
                        self.append(.error, "Listen failed: \(error.localizedDescription)")
                    case .cancelled:
                        if self.epoch == token { self.isRunning = false }
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn, token: token)
            }
            listener.start(queue: queue)
        } catch {
            errorMessage = error.localizedDescription
            append(.error, error.localizedDescription)
        }
    }

    public func stop() {
        stop(resetEpoch: true)
    }

    public func clearLogs() {
        logs.removeAll()
        requestCount = 0
    }

    private func stop(resetEpoch: Bool) {
        if resetEpoch { epoch += 1 }
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ conn: NWConnection, token: UInt64) {
        conn.start(queue: queue)
        receive(conn, buffer: Data(), token: token)
    }

    private func receive(_ conn: NWConnection, buffer: Data, token: UInt64) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self, !self.isDisposed, self.epoch == token else {
                conn.cancel()
                return
            }
            var next = buffer
            if let content { next.append(content) }
            if let request = HTTPRequestParser.parse(next) {
                self.respond(to: request, on: conn)
                return
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(conn, buffer: next, token: token)
        }
    }

    private func respond(to request: HTTPRequestParser.Request, on conn: NWConnection) {
        let summary = "\(request.method) \(request.path)"
        DispatchQueue.main.async {
            self.requestCount += 1
            self.append(.receive, summary + "\n" + request.rawHead, payload: request.body)
        }

        let status: Int
        let type: String
        let body: Data
        if mode == .echo {
            status = 200
            type = "text/plain; charset=utf-8"
            var dump = request.rawHead
            if !request.body.isEmpty {
                dump += "\n" + (String(data: request.body, encoding: .utf8) ?? HexUtils.dataToHexString(request.body))
            }
            body = Data(dump.utf8)
        } else {
            status = statusCode
            type = contentType
            body = Data(responseBody.utf8)
        }

        let reason = HTTPRequestParser.reason(status)
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        response += "Content-Type: \(type)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"
        var payload = Data(response.utf8)
        payload.append(body)
        conn.send(content: payload, completion: .contentProcessed { _ in
            conn.cancel()
        })
        DispatchQueue.main.async {
            self.append(.send, "\(status) \(reason) (\(body.count) B)")
        }
    }

    private func append(_ direction: LogDirection, _ text: String, payload: Data? = nil) {
        logs.append(
            NetworkLogItem(
                direction: direction,
                content: text,
                hexRepresentation: payload.map { HexUtils.dataToHexString($0) },
                byteCount: payload?.count ?? text.utf8.count,
                payload: payload
            )
        )
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }

    deinit {
        isDisposed = true
        listener?.cancel()
    }
}

enum HTTPRequestParser {
    struct Request {
        var method: String
        var path: String
        var rawHead: String
        var body: Data
    }

    static func parse(_ data: Data) -> Request? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headData = data.subdata(in: data.startIndex..<range.lowerBound)
        guard let head = String(data: headData, encoding: .isoLatin1) else { return nil }
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let start = lines.first else { return nil }
        let parts = start.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in
            guard let sep = line.firstIndex(of: ":") else { return nil }
            let key = line[..<sep].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            return (key.lowercased(), value)
        })
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = range.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= length else { return nil }
        let body = data.subdata(in: bodyStart..<data.index(bodyStart, offsetBy: length))
        return Request(method: String(parts[0]), path: String(parts[1]), rawHead: head, body: body)
    }

    static func reason(_ code: Int) -> String {
        HTTPStatus.phrase(code)
    }
}
