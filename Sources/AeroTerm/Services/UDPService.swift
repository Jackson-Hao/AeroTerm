import Foundation
import Network
import Combine

public enum UDPMode: String, CaseIterable, Identifiable, Sendable {
    case unicast = "单播 (Unicast)"
    case multicast = "多播组 (Multicast)"
    case broadcast = "广播 (Broadcast)"

    public var id: String { rawValue }
}

public final class UDPEngine: ObservableObject, @unchecked Sendable {
    @Published public var isListening = false
    @Published public var mode: UDPMode = .unicast
    @Published public var localPort: Int = 9000
    @Published public var targetHost: String = "127.0.0.1"
    @Published public var targetPort: Int = 9000
    @Published public var multicastGroup: String = "239.255.0.1"

    @Published public var logs: [NetworkLogItem] = []
    @Published public var txBytes: Int = 0
    @Published public var rxBytes: Int = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.aeroterm.udp", qos: .userInitiated)
    private var isDisposed = false

    public init() {}

    public func startListening() {
        stopListening()

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(localPort)) else {
            appendLog(direction: .error, content: "无效的本地端口: \(localPort)")
            return
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self = self, !self.isDisposed else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.appendLog(direction: .system, content: "UDP 监听已在端口 \(self.localPort) 就绪 (\(self.mode.rawValue))")
                    case .failed, .cancelled:
                        self.isListening = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                self?.handleInboundConnection(conn)
            }

            listener.start(queue: queue)
        } catch {
            appendLog(direction: .error, content: "创建 UDP 监听器异常: \(error.localizedDescription)")
        }
    }

    public func stopListening() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.isListening = false
        }
    }

    private func handleInboundConnection(_ conn: NWConnection) {
        guard !isDisposed else { return }
        let ep = "\(conn.endpoint)"
        conn.start(queue: queue)
        receiveNextMessage(on: conn, endpoint: ep)
    }

    private func receiveNextMessage(on conn: NWConnection, endpoint: String) {
        guard !isDisposed else { return }
        conn.receiveMessage { [weak self, weak conn] data, _, isComplete, error in
            guard let self = self, !self.isDisposed else { return }
            if let data = data, !data.isEmpty {
                DispatchQueue.main.async {
                    guard !self.isDisposed else { return }
                    self.rxBytes += data.count
                    let str = String(data: data, encoding: .utf8) ?? "<二进制 UDP 数据>"
                    let hex = HexUtils.dataToHexString(data)
                    self.appendLog(direction: .receive, content: str, hex: hex, bytes: data.count, remote: endpoint)
                }
            }
            if error == nil && !isComplete, let activeConn = conn {
                self.receiveNextMessage(on: activeConn, endpoint: endpoint)
            }
        }
    }

    public func send(data: Data, formatIsHex: Bool = false) {
        guard !isDisposed else { return }
        let destinationHost: String
        let destinationPort: Int

        switch mode {
        case .unicast:
            destinationHost = targetHost
            destinationPort = targetPort
        case .broadcast:
            destinationHost = "255.255.255.255"
            destinationPort = targetPort
        case .multicast:
            destinationHost = multicastGroup
            destinationPort = targetPort
        }

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(destinationPort)) else { return }

        let nwHost = NWEndpoint.Host(destinationHost)
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self, !self.isDisposed else { return }
            switch state {
            case .ready:
                conn.send(content: data, completion: .contentProcessed { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self, !self.isDisposed else { return }
                        if error == nil {
                            self.txBytes += data.count
                            let str = String(data: data, encoding: .utf8) ?? "<二进制数据>"
                            let hex = HexUtils.dataToHexString(data)
                            self.appendLog(
                                direction: .send,
                                content: "\(self.mode == .broadcast ? "[广播] " : "")\(str)",
                                hex: hex,
                                bytes: data.count,
                                remote: "\(destinationHost):\(destinationPort)"
                            )
                        }
                    }
                    conn.cancel()
                })
            case .failed:
                conn.cancel()
            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    public func sendText(_ text: String, addNewline: Bool = false) {
        var str = text
        if addNewline { str += "\n" }
        if let data = str.data(using: .utf8) {
            send(data: data, formatIsHex: false)
        }
    }

    public func sendHex(_ hex: String) {
        if let data = HexUtils.hexStringToData(hex) {
            send(data: data, formatIsHex: true)
        }
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
        stopListening()
    }
}
