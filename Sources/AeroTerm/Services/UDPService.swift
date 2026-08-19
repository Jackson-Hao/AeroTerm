import Foundation
import Network
import Combine

public final class UDPEngine: ObservableObject, @unchecked Sendable {
    @Published public var isListening = false
    @Published public var mode: UDPMode = .unicast
    @Published public var localPort: Int = 8080
    @Published public var targetHost: String = "127.0.0.1"
    @Published public var targetPort: Int = 8080
    @Published public var errorMessage: String? = nil
    @Published public var logs: [NetworkLogItem] = []
    @Published public var txBytes: Int = 0
    @Published public var rxBytes: Int = 0
    @Published public var receiveFileURL: URL? = nil
    @Published public var fileTransferLabel: String? = nil

    private var listener: NWListener?
    private var multicastGroup: NWConnectionGroup?
    private var inbound: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.aeroterm.udp", qos: .userInitiated)
    private var isDisposed = false
    private var epoch: UInt64 = 0
    private var receiveFileAccess = false

    public init() {}

    public func start(
        mode: UDPMode,
        localPort: Int,
        targetHost: String,
        targetPort: Int
    ) {
        epoch += 1
        let token = epoch
        tearDown(resetFlags: false)
        self.mode = mode
        self.localPort = localPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        errorMessage = nil

        guard (1...65535).contains(localPort),
              let bindPort = NWEndpoint.Port(rawValue: UInt16(localPort))
        else {
            errorMessage = "Invalid local port: \(localPort)"
            appendLog(direction: .error, content: "Invalid local port: \(localPort)")
            return
        }

        switch mode {
        case .multicast:
            startMulticast(group: targetHost, port: bindPort, token: token)
        case .unicast, .broadcast:
            startListener(on: bindPort, token: token)
        }
    }

    public func stop() {
        epoch += 1
        tearDown(resetFlags: true)
    }

    public func send(_ data: Data) {
        guard !isDisposed, !data.isEmpty else { return }
        if mode == .multicast, let multicastGroup {
            let remote = "\(targetHost):\(targetPort)"
            multicastGroup.send(content: data) { error in
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isDisposed else { return }
                    if let error {
                        self.appendLog(direction: .error, content: "Send failed: \(error.localizedDescription)")
                        return
                    }
                    self.txBytes += data.count
                    self.appendLog(
                        direction: .send,
                        content: TCPTextEncoding.utf8.decode(data),
                        bytes: data.count,
                        remote: remote,
                        payload: data
                    )
                }
            }
            return
        }

        let destinationHost: String
        switch mode {
        case .unicast:
            destinationHost = targetHost
        case .broadcast:
            destinationHost = targetHost.isEmpty || targetHost == "0.0.0.0" ? "255.255.255.255" : targetHost
        case .multicast:
            destinationHost = targetHost
        }
        guard (1...65535).contains(targetPort),
              let destPort = NWEndpoint.Port(rawValue: UInt16(targetPort))
        else {
            appendLog(direction: .error, content: "Invalid target port: \(targetPort)")
            return
        }

        let params = makeParameters(broadcast: mode == .broadcast)
        if (1...65535).contains(localPort),
           let localNW = NWEndpoint.Port(rawValue: UInt16(localPort)) {
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: localNW)
        }
        let conn = NWConnection(host: NWEndpoint.Host(destinationHost), port: destPort, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isDisposed else { return }
            switch state {
            case .ready:
                conn.send(content: data, completion: .contentProcessed { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self, !self.isDisposed else { return }
                        if let error {
                            self.appendLog(direction: .error, content: "Send failed: \(error.localizedDescription)")
                        } else {
                            self.txBytes += data.count
                            self.appendLog(
                                direction: .send,
                                content: TCPTextEncoding.utf8.decode(data),
                                bytes: data.count,
                                remote: "\(destinationHost):\(self.targetPort)",
                                payload: data
                            )
                        }
                    }
                    conn.cancel()
                })
            case .failed(let error):
                DispatchQueue.main.async {
                    self.appendLog(direction: .error, content: "Send failed: \(error.localizedDescription)")
                }
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    public func sendFile(_ url: URL) {
        Task { [weak self] in
            await self?.performSendFile(url)
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

    private func startListener(on port: NWEndpoint.Port, token: UInt64) {
        do {
            let listener = try NWListener(using: makeParameters(broadcast: mode == .broadcast), on: port)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self, !self.isDisposed, self.epoch == token else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.appendLog(
                            direction: .system,
                            content: "Listening UDP \(self.mode.title) on :\(self.localPort)"
                        )
                    case .failed(let error):
                        self.isListening = false
                        self.errorMessage = error.localizedDescription
                        self.appendLog(direction: .error, content: "Listen failed: \(error.localizedDescription)")
                    case .cancelled:
                        if self.epoch == token {
                            self.isListening = false
                        }
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleInbound(conn, token: token)
            }
            listener.start(queue: queue)
        } catch {
            appendLog(direction: .error, content: "Listener error: \(error.localizedDescription)")
        }
    }

    private func startMulticast(group: String, port: NWEndpoint.Port, token: UInt64) {
        do {
            let descriptor = try NWMulticastGroup(for: [.hostPort(host: NWEndpoint.Host(group), port: port)])
            let connectionGroup = NWConnectionGroup(with: descriptor, using: makeParameters(broadcast: false))
            multicastGroup = connectionGroup
            connectionGroup.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self, !self.isDisposed, self.epoch == token else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.appendLog(
                            direction: .system,
                            content: "Joined multicast \(group):\(self.localPort)"
                        )
                    case .failed(let error):
                        self.isListening = false
                        self.errorMessage = error.localizedDescription
                        self.appendLog(direction: .error, content: "Multicast failed: \(error.localizedDescription)")
                    case .cancelled:
                        if self.epoch == token {
                            self.isListening = false
                        }
                    default:
                        break
                    }
                }
            }
            connectionGroup.setReceiveHandler(maximumMessageSize: 65535, rejectOversizedMessages: false) { [weak self] message, content, _ in
                guard let self, !self.isDisposed, self.epoch == token, let data = content, !data.isEmpty else { return }
                let remote = message.remoteEndpoint.map { "\($0)" } ?? group
                DispatchQueue.main.async {
                    guard !self.isDisposed, self.epoch == token else { return }
                    self.rxBytes += data.count
                    self.appendLog(
                        direction: .receive,
                        content: TCPTextEncoding.utf8.decode(data),
                        bytes: data.count,
                        remote: remote,
                        payload: data
                    )
                    self.writeReceiveFile(data)
                }
            }
            connectionGroup.start(queue: queue)
        } catch {
            errorMessage = error.localizedDescription
            appendLog(direction: .error, content: "Multicast join failed: \(error.localizedDescription)")
        }
    }

    private func handleInbound(_ conn: NWConnection, token: UInt64) {
        guard !isDisposed, epoch == token else {
            conn.cancel()
            return
        }
        inbound[ObjectIdentifier(conn)] = conn
        conn.start(queue: queue)
        receiveLoop(conn, token: token)
    }

    private func receiveLoop(_ conn: NWConnection, token: UInt64) {
        conn.receiveMessage { [weak self, weak conn] data, _, _, error in
            guard let self, let conn, !self.isDisposed, self.epoch == token else { return }
            if let data, !data.isEmpty {
                let remote = "\(conn.endpoint)"
                DispatchQueue.main.async {
                    guard !self.isDisposed, self.epoch == token else { return }
                    self.rxBytes += data.count
                    self.appendLog(
                        direction: .receive,
                        content: TCPTextEncoding.utf8.decode(data),
                        bytes: data.count,
                        remote: remote,
                        payload: data
                    )
                    self.writeReceiveFile(data)
                }
            }
            if error != nil {
                self.inbound[ObjectIdentifier(conn)] = nil
                conn.cancel()
                return
            }
            // UDP datagrams are complete messages; keep the socket open.
            self.receiveLoop(conn, token: token)
        }
    }

    private func performSendFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            await MainActor.run { self.fileTransferLabel = "Sending \(url.lastPathComponent)" }
            var offset = 0
            while offset < data.count {
                let end = min(offset + TCPIO.chunkSize, data.count)
                let chunk = data.subdata(in: offset..<end)
                await MainActor.run { self.send(chunk) }
                offset = end
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

    private func makeParameters(broadcast: Bool) -> NWParameters {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true
        if broadcast, let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        return params
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
        multicastGroup?.cancel()
        multicastGroup = nil
        for (_, conn) in inbound {
            conn.cancel()
        }
        inbound.removeAll()
        if resetFlags {
            isListening = false
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

    deinit {
        isDisposed = true
        if receiveFileAccess, let url = receiveFileURL {
            url.stopAccessingSecurityScopedResource()
        }
        listener?.cancel()
        multicastGroup?.cancel()
        for (_, conn) in inbound { conn.cancel() }
    }
}
