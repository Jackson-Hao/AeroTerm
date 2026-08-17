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

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aeroterm.tcpclient", qos: .userInitiated)
    private var isDisposed = false

    public init() {}

    public func connect(host: String, port: Int) {
        disconnect()
        isConnecting = true
        errorMessage = nil

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            errorMessage = "无效的端口号: \(port)"
            isConnecting = false
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 15
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self, !self.isDisposed else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.isConnecting = false
                    self.appendLog(direction: .system, content: "已连接到 \(host):\(port)")
                    self.startReceiving()
                case .failed(let error):
                    self.isConnected = false
                    self.isConnecting = false
                    self.errorMessage = error.localizedDescription
                    self.appendLog(direction: .error, content: "连接失败: \(error.localizedDescription)")
                case .cancelled:
                    self.isConnected = false
                    self.isConnecting = false
                default:
                    break
                }
            }
        }

        conn.start(queue: queue)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.isConnected = false
            self.isConnecting = false
        }
    }

    public func send(data: Data, formatIsHex: Bool = false) {
        guard let connection = connection, isConnected, !isDisposed else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self, !self.isDisposed else { return }
                if let error = error {
                    self.appendLog(direction: .error, content: "发送失败: \(error.localizedDescription)")
                } else {
                    self.txBytes += data.count
                    let content = String(data: data, encoding: .utf8) ?? "<非 UTF-8 二进制数据>"
                    let hex = HexUtils.dataToHexString(data)
                    self.appendLog(direction: .send, content: content, hex: hex, bytes: data.count)
                }
            }
        })
    }

    public func sendText(_ text: String, addNewline: Bool = false) {
        var str = text
        if addNewline { str += "\n" }
        if let data = str.data(using: .utf8) {
            send(data: data, formatIsHex: false)
        }
    }

    public func sendHex(_ hexString: String) {
        if let data = HexUtils.hexStringToData(hexString) {
            send(data: data, formatIsHex: true)
        }
    }

    private func startReceiving() {
        guard let connection = connection, !isDisposed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self, !self.isDisposed else { return }

            if let data = content, !data.isEmpty {
                DispatchQueue.main.async {
                    guard !self.isDisposed else { return }
                    self.rxBytes += data.count
                    let str = String(data: data, encoding: .utf8) ?? "<非 UTF-8 数据>"
                    let hex = HexUtils.dataToHexString(data)
                    self.appendLog(direction: .receive, content: str, hex: hex, bytes: data.count)
                }
            }

            if isComplete {
                DispatchQueue.main.async {
                    guard !self.isDisposed else { return }
                    self.appendLog(direction: .system, content: "远端关闭了连接")
                    self.disconnect()
                }
            } else if error != nil {
                DispatchQueue.main.async {
                    self.disconnect()
                }
            } else {
                self.startReceiving()
            }
        }
    }

    public func clearLogs() {
        logs.removeAll()
        txBytes = 0
        rxBytes = 0
    }

    private func appendLog(direction: LogDirection, content: String, hex: String? = nil, bytes: Int = 0) {
        guard !isDisposed else { return }
        let item = NetworkLogItem(
            direction: direction,
            content: content,
            hexRepresentation: hex,
            byteCount: bytes
        )
        logs.append(item)
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }

    deinit {
        isDisposed = true
        disconnect()
    }
}

public final class TCPServerEngine: ObservableObject, @unchecked Sendable {
    @Published public var isRunning = false
    @Published public var listeningPort: Int = 8080
    @Published public var clientEndpoints: [String] = []
    @Published public var logs: [NetworkLogItem] = []
    @Published public var autoEcho: Bool = false
    @Published public var txBytes: Int = 0
    @Published public var rxBytes: Int = 0

    private var listener: NWListener?
    private var activeConnections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.aeroterm.tcpserver", qos: .userInitiated)
    private var isDisposed = false

    public init() {}

    public func start(port: Int) {
        stop()
        listeningPort = port
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            appendLog(direction: .error, content: "无效的监听端口: \(port)")
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self = self, !self.isDisposed else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.appendLog(direction: .system, content: "TCP 服务器已在端口 \(port) 启动监听")
                    case .failed, .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
        } catch {
            appendLog(direction: .error, content: "创建监听器错误: \(error.localizedDescription)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.isRunning = false
            self.clientEndpoints.removeAll()
        }
    }

    private func handleNewConnection(_ conn: NWConnection) {
        guard !isDisposed else { return }
        let ep = "\(conn.endpoint)"
        activeConnections[ep] = conn

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.clientEndpoints = Array(self.activeConnections.keys)
            self.appendLog(direction: .system, content: "客户端已连接: \(ep)", remote: ep)
        }

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self, !self.isDisposed else { return }
            switch state {
            case .cancelled, .failed:
                self.activeConnections.removeValue(forKey: ep)
                DispatchQueue.main.async {
                    guard !self.isDisposed else { return }
                    self.clientEndpoints = Array(self.activeConnections.keys)
                    self.appendLog(direction: .system, content: "客户端已断开: \(ep)", remote: ep)
                }
            default:
                break
            }
        }

        receiveFromClient(conn, endpoint: ep)
        conn.start(queue: queue)
    }

    private func receiveFromClient(_ conn: NWConnection, endpoint: String) {
        guard !isDisposed else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, !self.isDisposed else { return }
            if let data = data, !data.isEmpty {
                DispatchQueue.main.async {
                    guard !self.isDisposed else { return }
                    self.rxBytes += data.count
                    let str = String(data: data, encoding: .utf8) ?? "<二进制数据>"
                    let hex = HexUtils.dataToHexString(data)
                    self.appendLog(direction: .receive, content: str, hex: hex, bytes: data.count, remote: endpoint)

                    if self.autoEcho {
                        self.sendToEndpoint(endpoint: endpoint, data: data)
                    }
                }
            }

            if isComplete || error != nil {
                conn.cancel()
                self.activeConnections.removeValue(forKey: endpoint)
                DispatchQueue.main.async {
                    guard !self.isDisposed else { return }
                    self.clientEndpoints = Array(self.activeConnections.keys)
                }
            } else {
                self.receiveFromClient(conn, endpoint: endpoint)
            }
        }
    }

    public func broadcast(data: Data) {
        guard !isDisposed else { return }
        for (ep, conn) in activeConnections {
            conn.send(content: data, completion: .contentProcessed { [weak self] _ in
                DispatchQueue.main.async {
                    self?.txBytes += data.count
                }
            })
            let str = String(data: data, encoding: .utf8) ?? "<二进制>"
            appendLog(direction: .send, content: "广播 -> \(ep): \(str)", hex: HexUtils.dataToHexString(data), bytes: data.count)
        }
    }

    public func sendToEndpoint(endpoint: String, data: Data) {
        guard !isDisposed, let conn = activeConnections[endpoint] else { return }
        conn.send(content: data, completion: .contentProcessed { [weak self] _ in
            DispatchQueue.main.async {
                self?.txBytes += data.count
            }
        })
        let str = String(data: data, encoding: .utf8) ?? "<二进制>"
        appendLog(direction: .send, content: "发往 \(endpoint): \(str)", hex: HexUtils.dataToHexString(data), bytes: data.count, remote: endpoint)
    }

    public func clearLogs() {
        logs.removeAll()
        txBytes = 0
        rxBytes = 0
    }

    private func appendLog(direction: LogDirection, content: String, hex: String? = nil, bytes: Int = 0, remote: String? = nil) {
        guard !isDisposed else { return }
        let item = NetworkLogItem(
            direction: direction,
            content: content,
            hexRepresentation: hex,
            byteCount: bytes,
            remoteEndpoint: remote
        )
        logs.append(item)
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }

    deinit {
        isDisposed = true
        stop()
    }
}
