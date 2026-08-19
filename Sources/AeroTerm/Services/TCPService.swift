import Foundation
import Network
import Combine

public final class TCPClientEngine: ObservableObject, @unchecked Sendable {
    @Published public var isConnected = false
    @Published public var isConnecting = false
    @Published public var errorMessage: String? = nil
    @Published public var logs: [NetworkLogItem] = []
    @Published public var txBytes: Int = 0
    @Published public var rxBytes: Int = 0
    @Published public var receiveFileURL: URL? = nil
    @Published public var fileTransferLabel: String? = nil

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aeroterm.tcpclient", qos: .userInitiated)
    private var isDisposed = false
    private var epoch: UInt64 = 0
    private var receiveFileAccess = false

    public init() {}

    public func connect(host: String, port: Int, localPort: Int = 0) {
        epoch += 1
        let token = epoch
        tearDown(resetFlags: false)
        isConnecting = true
        errorMessage = nil

        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else {
            errorMessage = "Invalid port: \(port)"
            isConnecting = false
            return
        }

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 15
        let params = NWParameters(tls: nil, tcp: tcp)
        if localPort > 0 {
            guard (1...65535).contains(localPort),
                  let localNW = NWEndpoint.Port(rawValue: UInt16(localPort))
            else {
                errorMessage = "Invalid local port: \(localPort)"
                isConnecting = false
                return
            }
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: localNW)
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self, !self.isDisposed, self.epoch == token else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.isConnecting = false
                    let localNote = localPort > 0 ? " from :\(localPort)" : ""
                    self.appendLog(direction: .system, content: "Connected to \(host):\(port)\(localNote)")
                    self.startReceiving(conn, token: token)
                case .failed(let error):
                    self.isConnected = false
                    self.isConnecting = false
                    self.errorMessage = error.localizedDescription
                    self.appendLog(direction: .error, content: "Connect failed: \(error.localizedDescription)")
                case .cancelled:
                    if self.epoch == token {
                        self.isConnected = false
                        self.isConnecting = false
                    }
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)
    }

    public func disconnect() {
        epoch += 1
        tearDown(resetFlags: true)
    }

    public func send(_ data: Data, note: String? = nil) {
        guard let connection, isConnected, !isDisposed, !data.isEmpty else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                guard let self, !self.isDisposed else { return }
                if let error {
                    self.appendLog(direction: .error, content: "Send failed: \(error.localizedDescription)")
                    return
                }
                self.txBytes += data.count
                self.appendLog(
                    direction: .send,
                    content: note ?? TCPTextEncoding.utf8.decode(data),
                    bytes: data.count,
                    payload: data
                )
            }
        })
    }

    public func sendFile(_ url: URL) {
        guard isConnected, !isDisposed else { return }
        Task { [weak self] in
            await self?.performSendFile(url)
        }
    }

    private func performSendFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var sent = 0
            let total = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            await MainActor.run { self.fileTransferLabel = "Sending \(url.lastPathComponent)" }
            while true {
                guard !isDisposed, isConnected else { break }
                guard let chunk = try handle.read(upToCount: TCPIO.chunkSize), !chunk.isEmpty else { break }
                try await sendAsync(chunk)
                sent += chunk.count
                let copied = sent
                await MainActor.run {
                    self.txBytes += chunk.count
                    if total > 0 {
                        self.fileTransferLabel = "Sending \(url.lastPathComponent) \(copied)/\(total)"
                    }
                }
            }
            await MainActor.run {
                self.fileTransferLabel = nil
                self.appendLog(
                    direction: .system,
                    content: "Sent file \(url.lastPathComponent) (\(HexUtils.formatByteCount(sent)))"
                )
            }
        } catch {
            await MainActor.run {
                self.fileTransferLabel = nil
                self.appendLog(direction: .error, content: "File send failed: \(error.localizedDescription)")
            }
        }
    }

    private func sendAsync(_ data: Data) async throws {
        guard let connection else { throw CocoaError(.fileWriteUnknown) }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    public func setReceiveFile(_ url: URL?) {
        if receiveFileAccess, let previous = receiveFileURL {
            previous.stopAccessingSecurityScopedResource()
            receiveFileAccess = false
        }
        receiveFileURL = url
        if let url {
            receiveFileAccess = url.startAccessingSecurityScopedResource()
            appendLog(direction: .system, content: "Saving received bytes to \(url.path)")
        }
    }

    public func clearLogs() {
        logs.removeAll()
        txBytes = 0
        rxBytes = 0
    }

    private func startReceiving(_ conn: NWConnection, token: UInt64) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self, !self.isDisposed, self.epoch == token else { return }
            if let data = content, !data.isEmpty {
                DispatchQueue.main.async {
                    guard !self.isDisposed, self.epoch == token else { return }
                    self.rxBytes += data.count
                    self.appendLog(
                        direction: .receive,
                        content: TCPTextEncoding.utf8.decode(data),
                        bytes: data.count,
                        payload: data
                    )
                    self.writeReceiveFile(data)
                }
            }
            if isComplete {
                DispatchQueue.main.async {
                    guard !self.isDisposed, self.epoch == token else { return }
                    self.appendLog(direction: .system, content: "Remote closed the connection")
                    self.disconnect()
                }
            } else if error != nil {
                DispatchQueue.main.async {
                    guard !self.isDisposed, self.epoch == token else { return }
                    self.disconnect()
                }
            } else {
                self.startReceiving(conn, token: token)
            }
        }
    }

    private func writeReceiveFile(_ data: Data) {
        guard let url = receiveFileURL else { return }
        do {
            try TCPIO.append(data, to: url)
        } catch {
            appendLog(direction: .error, content: "Receive file write failed: \(error.localizedDescription)")
        }
    }

    private func tearDown(resetFlags: Bool) {
        connection?.cancel()
        connection = nil
        if resetFlags {
            isConnected = false
            isConnecting = false
        }
    }

    private func appendLog(
        direction: LogDirection,
        content: String,
        bytes: Int = 0,
        payload: Data? = nil
    ) {
        guard !isDisposed else { return }
        logs.append(
            NetworkLogItem(
                direction: direction,
                content: content,
                hexRepresentation: payload.map { HexUtils.dataToHexString($0) },
                byteCount: bytes,
                payload: payload
            )
        )
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }

    deinit {
        isDisposed = true
        if receiveFileAccess, let url = receiveFileURL {
            url.stopAccessingSecurityScopedResource()
        }
        connection?.cancel()
    }
}

public final class TCPServerEngine: ObservableObject, @unchecked Sendable {
    @Published public var isRunning = false
    @Published public var listeningPort: Int = 8080
    @Published public var clientEndpoints: [String] = []
    @Published public var selectedEndpoint: String? = nil
    @Published public var logs: [NetworkLogItem] = []
    @Published public var autoEcho: Bool = false
    @Published public var txBytes: Int = 0
    @Published public var rxBytes: Int = 0
    @Published public var receiveFileURL: URL? = nil
    @Published public var fileTransferLabel: String? = nil
    @Published public var errorMessage: String? = nil

    private var listener: NWListener?
    private var activeConnections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.aeroterm.tcpserver", qos: .userInitiated)
    private var isDisposed = false
    private var epoch: UInt64 = 0
    private var receiveFileAccess = false

    public init() {}

    public func start(port: Int) {
        epoch += 1
        let token = epoch
        tearDown(resetFlags: false)
        listeningPort = port
        errorMessage = nil

        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else {
            errorMessage = "Invalid listen port: \(port)"
            appendLog(direction: .error, content: "Invalid listen port: \(port)")
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
                        self.appendLog(direction: .system, content: "Listening on port \(port)")
                    case .failed(let error):
                        self.isRunning = false
                        self.errorMessage = error.localizedDescription
                        self.appendLog(direction: .error, content: "Listen failed: \(error.localizedDescription)")
                    case .cancelled:
                        if self.epoch == token {
                            self.isRunning = false
                        }
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection, token: token)
            }
            listener.start(queue: queue)
        } catch {
            appendLog(direction: .error, content: "Listener error: \(error.localizedDescription)")
        }
    }

    public func stop() {
        epoch += 1
        tearDown(resetFlags: true)
    }

    public func send(_ data: Data, note: String? = nil) {
        guard !isDisposed, !data.isEmpty else { return }
        if let selectedEndpoint, let conn = activeConnections[selectedEndpoint] {
            send(data, on: conn, endpoint: selectedEndpoint, note: note)
            return
        }
        broadcast(data, note: note)
    }

    public func broadcast(_ data: Data, note: String? = nil) {
        guard !isDisposed, !data.isEmpty else { return }
        for (endpoint, conn) in activeConnections {
            send(data, on: conn, endpoint: endpoint, note: note ?? "Broadcast", logEach: true)
        }
    }

    public func sendFile(_ url: URL) {
        guard isRunning, !activeConnections.isEmpty else { return }
        let targets: [(String, NWConnection)]
        if let selectedEndpoint, let conn = activeConnections[selectedEndpoint] {
            targets = [(selectedEndpoint, conn)]
        } else {
            targets = activeConnections.map { ($0.key, $0.value) }
        }
        Task { [weak self] in
            await self?.performSendFile(url, targets: targets)
        }
    }

    private func performSendFile(_ url: URL, targets: [(String, NWConnection)]) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            await MainActor.run { self.fileTransferLabel = "Sending \(url.lastPathComponent)" }
            for (endpoint, conn) in targets {
                var offset = 0
                while offset < data.count {
                    let end = min(offset + TCPIO.chunkSize, data.count)
                    try await sendAsync(data.subdata(in: offset..<end), on: conn)
                    offset = end
                }
                await MainActor.run {
                    self.txBytes += data.count
                    self.appendLog(
                        direction: .send,
                        content: "File \(url.lastPathComponent) -> \(endpoint)",
                        bytes: data.count,
                        remote: endpoint
                    )
                }
            }
            await MainActor.run {
                self.fileTransferLabel = nil
                self.appendLog(
                    direction: .system,
                    content: "Sent file \(url.lastPathComponent) (\(HexUtils.formatByteCount(data.count)))"
                )
            }
        } catch {
            await MainActor.run {
                self.fileTransferLabel = nil
                self.appendLog(direction: .error, content: "File send failed: \(error.localizedDescription)")
            }
        }
    }

    private func sendAsync(_ data: Data, on conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    public func setReceiveFile(_ url: URL?) {
        if receiveFileAccess, let previous = receiveFileURL {
            previous.stopAccessingSecurityScopedResource()
            receiveFileAccess = false
        }
        receiveFileURL = url
        if let url {
            receiveFileAccess = url.startAccessingSecurityScopedResource()
            appendLog(direction: .system, content: "Saving received bytes to \(url.path)")
        }
    }

    public func clearLogs() {
        logs.removeAll()
        txBytes = 0
        rxBytes = 0
    }

    private func send(
        _ data: Data,
        on conn: NWConnection,
        endpoint: String,
        note: String?,
        logEach: Bool = true
    ) {
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                guard let self, !self.isDisposed else { return }
                if let error {
                    self.appendLog(direction: .error, content: "Send failed: \(error.localizedDescription)", remote: endpoint)
                    return
                }
                self.txBytes += data.count
                if logEach {
                    self.appendLog(
                        direction: .send,
                        content: note ?? TCPTextEncoding.utf8.decode(data),
                        bytes: data.count,
                        remote: endpoint,
                        payload: data
                    )
                }
            }
        })
    }

    private func handleNewConnection(_ conn: NWConnection, token: UInt64) {
        guard !isDisposed, epoch == token else {
            conn.cancel()
            return
        }
        let endpoint = Self.label(for: conn)
        activeConnections[endpoint] = conn
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed, self.epoch == token else { return }
            self.clientEndpoints = Array(self.activeConnections.keys).sorted()
            if self.selectedEndpoint == nil {
                self.selectedEndpoint = endpoint
            }
            self.appendLog(direction: .system, content: "Client connected: \(endpoint)", remote: endpoint)
        }
        conn.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isDisposed else { return }
            if case .failed = state { self.dropClient(endpoint, token: token) }
            if case .cancelled = state { self.dropClient(endpoint, token: token) }
        }
        receiveFromClient(conn, endpoint: endpoint, token: token)
        conn.start(queue: queue)
    }

    private func receiveFromClient(_ conn: NWConnection, endpoint: String, token: UInt64) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.isDisposed, self.epoch == token else { return }
            if let data, !data.isEmpty {
                DispatchQueue.main.async {
                    guard !self.isDisposed, self.epoch == token else { return }
                    self.rxBytes += data.count
                    self.appendLog(
                        direction: .receive,
                        content: TCPTextEncoding.utf8.decode(data),
                        bytes: data.count,
                        remote: endpoint,
                        payload: data
                    )
                    self.writeReceiveFile(data)
                    if self.autoEcho {
                        self.send(data, on: conn, endpoint: endpoint, note: "Echo", logEach: true)
                    }
                }
            }
            if isComplete || error != nil {
                self.dropClient(endpoint, token: token)
                conn.cancel()
            } else {
                self.receiveFromClient(conn, endpoint: endpoint, token: token)
            }
        }
    }

    private func dropClient(_ endpoint: String, token: UInt64) {
        activeConnections.removeValue(forKey: endpoint)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed, self.epoch == token else { return }
            self.clientEndpoints = Array(self.activeConnections.keys).sorted()
            if self.selectedEndpoint == endpoint {
                self.selectedEndpoint = self.clientEndpoints.first
            }
            self.appendLog(direction: .system, content: "Client disconnected: \(endpoint)", remote: endpoint)
        }
    }

    private func writeReceiveFile(_ data: Data) {
        guard let url = receiveFileURL else { return }
        do {
            try TCPIO.append(data, to: url)
        } catch {
            appendLog(direction: .error, content: "Receive file write failed: \(error.localizedDescription)")
        }
    }

    private func tearDown(resetFlags: Bool) {
        listener?.cancel()
        listener = nil
        for (_, conn) in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        if resetFlags {
            isRunning = false
            clientEndpoints = []
            selectedEndpoint = nil
        }
    }

    private func appendLog(
        direction: LogDirection,
        content: String,
        bytes: Int = 0,
        remote: String? = nil,
        payload: Data? = nil
    ) {
        guard !isDisposed else { return }
        logs.append(
            NetworkLogItem(
                direction: direction,
                content: content,
                hexRepresentation: payload.map { HexUtils.dataToHexString($0) },
                byteCount: bytes,
                remoteEndpoint: remote,
                payload: payload
            )
        )
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }

    private static func label(for conn: NWConnection) -> String {
        switch conn.endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return "\(conn.endpoint)"
        }
    }

    deinit {
        isDisposed = true
        if receiveFileAccess, let url = receiveFileURL {
            url.stopAccessingSecurityScopedResource()
        }
        listener?.cancel()
        for (_, conn) in activeConnections { conn.cancel() }
    }
}


