import Foundation
import Network
import Combine

public final class TelnetEngine: ObservableObject, @unchecked Sendable {
    @Published public var isConnected = false
    @Published public var isConnecting = false
    @Published public var terminalOutput: String = ""
    @Published public var host: String = ""
    @Published public var port: Int = 23

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aeroterm.telnet", qos: .userInitiated)
    private var isDisposed = false

    public init() {}

    public func connect(host: String, port: Int = 23) {
        disconnect()
        self.host = host
        self.port = port
        self.isConnecting = true
        self.terminalOutput = "正在连接到 \(host):\(port)...\n"

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            self.isConnecting = false
            return
        }

        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self, !self.isDisposed else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.isConnecting = false
                    self.terminalOutput += "已建立连接到 \(host):\(port)\n\n"
                    self.startReceiving()
                case .failed, .cancelled:
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

    public func sendCommand(_ text: String) {
        guard let connection = connection, isConnected, !isDisposed else { return }
        let fullCmd = text + "\r\n"
        if let data = fullCmd.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func startReceiving() {
        guard let connection = connection, !isDisposed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self, !self.isDisposed else { return }

            if let data = data, !data.isEmpty {
                let filtered = self.processTelnetIAC(data)
                if let str = String(data: filtered, encoding: .utf8) ?? String(data: filtered, encoding: .ascii) {
                    DispatchQueue.main.async {
                        guard !self.isDisposed else { return }
                        self.terminalOutput += str
                        if self.terminalOutput.count > 50000 {
                            self.terminalOutput = String(self.terminalOutput.suffix(40000))
                        }
                    }
                }
            }

            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.disconnect()
                }
            } else {
                self.startReceiving()
            }
        }
    }

    private func processTelnetIAC(_ data: Data) -> Data {
        var cleanData = Data()
        var i = 0
        let bytes = [UInt8](data)
        while i < bytes.count {
            if bytes[i] == 0xFF {
                if i + 1 < bytes.count {
                    let cmd = bytes[i + 1]
                    if cmd >= 251 && cmd <= 254 {
                        if i + 2 < bytes.count {
                            i += 3
                            continue
                        }
                    }
                }
                i += 2
            } else {
                cleanData.append(bytes[i])
                i += 1
            }
        }
        return cleanData
    }

    deinit {
        isDisposed = true
        disconnect()
    }
}
