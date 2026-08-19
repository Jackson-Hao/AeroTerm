import Foundation
import Network
import AppKit
import SwiftUI
import SwiftTerm
import Combine

public enum TelnetConnectError: LocalizedError {
    case invalidPort
    case timeout
    case disconnected
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPort: return "Invalid Telnet port."
        case .timeout: return "Telnet connection timed out."
        case .disconnected: return "Telnet session disconnected."
        case .failed(let message): return message
        }
    }
}

enum TelnetConnector {
    public static func connect(host: String, port: Int) async throws -> NWConnection {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw TelnetConnectError.invalidPort
        }
        return try await withCheckedThrowingContinuation { continuation in
            let tcp = NWProtocolTCP.Options()
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 15
            let params = NWParameters(tls: nil, tcp: tcp)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
            let box = TelnetOnceBox(continuation: continuation, connection: connection)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.finish(.success(connection))
                case .failed(let error):
                    box.finish(.failure(TelnetConnectError.failed(error.localizedDescription)))
                case .cancelled:
                    box.finish(.failure(TelnetConnectError.disconnected))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}

private final class TelnetOnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<NWConnection, Error>
    private let connection: NWConnection

    init(continuation: CheckedContinuation<NWConnection, Error>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ result: Result<NWConnection, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        if case .failure = result {
            connection.cancel()
        }
        continuation.resume(with: result)
    }
}

@MainActor
public final class TelnetTerminalSession: ObservableObject {
    public let sessionID: UUID
    public let terminalView: TerminalView
    @Published public var isAlive: Bool = true

    private let engine: TelnetIOEngine
    private var themeSignature = ""

    public init(connection: NWConnection, sessionID: UUID, username: String, password: String?) {
        self.sessionID = sessionID
        let view = TerminalView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        view.focusRingType = .none
        self.terminalView = view
        self.engine = TelnetIOEngine(
            connection: connection,
            sessionID: sessionID,
            username: username,
            password: password,
            terminalView: view
        )
        view.terminalDelegate = engine
        applyTheme()
    }

    public func start() {
        engine.start()
        startKeepAlive()
    }

    public func attach(to container: NSView) {
        if let host = container as? TerminalHostView {
            host.install(terminalView)
        } else {
            TerminalAppearance.paintContainer(container)
            terminalView.pinFilling(container)
        }
        applyTheme()
    }

    public func detach(from container: NSView) {
        if let host = container as? TerminalHostView {
            host.uninstall(terminalView)
            return
        }
        if terminalView.superview === container {
            terminalView.removeFromSuperview()
        }
    }

    public func applyTheme() {
        TerminalAppearance.apply(to: terminalView, lastSignature: &themeSignature)
    }

    public func shutdown() async {
        engine.finish()
        isAlive = false
    }

    func handleDisconnect() {
        guard isAlive else { return }
        isAlive = false
        SessionManager.shared.markSessionDisconnected(id: sessionID)
    }

    private func startKeepAlive() {
        engine.keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: SSHKeepAlive.intervalNanoseconds)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if !self.engine.isConnected {
                    await MainActor.run { self.handleDisconnect() }
                    return
                }
                self.engine.sendKeepAlive()
            }
        }
    }
}

final class TelnetIOEngine: TerminalViewDelegate, @unchecked Sendable {
    private let connection: NWConnection
    private let sessionID: UUID
    private let username: String
    private let password: String?
    weak var terminalView: TerminalView?
    var keepAliveTask: Task<Void, Never>?

    private let queue = DispatchQueue(label: "com.aeroterm.telnet.io", qos: .userInitiated)
    private var finished = false
    private var started = false
    private var loginSent = false
    private var passwordSent = false
    private var recentText = ""
    private var cols = 80
    private var rows = 24
    private(set) var isConnected = true

    init(
        connection: NWConnection,
        sessionID: UUID,
        username: String,
        password: String?,
        terminalView: TerminalView
    ) {
        self.connection = connection
        self.sessionID = sessionID
        self.username = username
        self.password = password
        self.terminalView = terminalView
    }

    func start() {
        guard !started else { return }
        started = true
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.handleRemoteClose()
            default:
                break
            }
        }
        receiveLoop()
    }

    func finish() {
        finished = true
        isConnected = false
        keepAliveTask?.cancel()
        keepAliveTask = nil
        connection.cancel()
    }

    func sendKeepAlive() {
        sendRaw(Data([TelnetIAC.iac, TelnetIAC.nop]))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard !finished, newCols >= 10, newRows >= 5 else { return }
        cols = newCols
        rows = newRows
        sendNAWS()
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !finished else { return }
        var escaped = Data()
        escaped.reserveCapacity(data.count)
        for byte in data {
            escaped.append(byte)
            if byte == TelnetIAC.iac {
                escaped.append(TelnetIAC.iac)
            }
        }
        sendRaw(escaped)
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                let text = self.processIncoming(data)
                if !text.isEmpty {
                    awaitFeed(text)
                    considerLogin(text)
                }
            }
            if isComplete || error != nil {
                handleRemoteClose()
                return
            }
            receiveLoop()
        }
    }

    private func handleRemoteClose() {
        guard !finished else { return }
        finished = true
        isConnected = false
        let id = sessionID
        DispatchQueue.main.async {
            SessionManager.shared.telnetSessions[id]?.handleDisconnect()
        }
    }

    private func awaitFeed(_ text: String) {
        DispatchQueue.main.async {
            self.terminalView?.feed(text: text)
        }
    }

    private func sendCredential(_ line: String) {
        var payload = Data(line.utf8)
        payload.append(0x0D)
        sendRaw(payload)
    }

    private func sendRaw(_ data: Data) {
        guard !finished, !data.isEmpty else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func considerLogin(_ text: String) {
        recentText += text
        if recentText.count > 400 {
            recentText = String(recentText.suffix(300))
        }
        let line = recentText
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .last
            .map(String.init) ?? recentText
        let prompt = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !loginSent, !username.isEmpty, isLoginPrompt(prompt) {
            loginSent = true
            queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.sendCredential(self?.username ?? "")
            }
            return
        }
        if loginSent, !passwordSent, let password, !password.isEmpty, isPasswordPrompt(prompt) {
            passwordSent = true
            queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.sendCredential(password)
            }
        }
    }

    private func isLoginPrompt(_ prompt: String) -> Bool {
        prompt == "login:" || prompt.hasSuffix("login:") || prompt.hasSuffix("username:")
    }

    private func isPasswordPrompt(_ prompt: String) -> Bool {
        prompt == "password:" || prompt.hasSuffix("password:")
    }

    private func sendNAWS() {
        let width = UInt16(clamping: cols)
        let height = UInt16(clamping: rows)
        sendRaw(Data([
            TelnetIAC.iac, TelnetIAC.sb, TelnetIAC.optNAWS,
            UInt8(width >> 8), UInt8(width & 0xFF),
            UInt8(height >> 8), UInt8(height & 0xFF),
            TelnetIAC.iac, TelnetIAC.se
        ]))
    }

    private func sendOption(_ command: UInt8, _ option: UInt8) {
        sendRaw(Data([TelnetIAC.iac, command, option]))
    }

    private func processIncoming(_ data: Data) -> String {
        var output = Data()
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            if byte != TelnetIAC.iac {
                output.append(byte)
                i = data.index(after: i)
                continue
            }
            let cmdIndex = data.index(after: i)
            guard cmdIndex < data.endIndex else { break }
            let command = data[cmdIndex]
            switch command {
            case TelnetIAC.iac:
                output.append(TelnetIAC.iac)
                i = data.index(after: cmdIndex)
            case TelnetIAC.nop, TelnetIAC.dm, TelnetIAC.brk, TelnetIAC.ip, TelnetIAC.ao, TelnetIAC.ayt, TelnetIAC.ec, TelnetIAC.el, TelnetIAC.ga:
                i = data.index(after: cmdIndex)
            case TelnetIAC.will, TelnetIAC.wont, TelnetIAC.do, TelnetIAC.dont:
                let optIndex = data.index(after: cmdIndex)
                guard optIndex < data.endIndex else { return decode(output) }
                handleOption(command: command, option: data[optIndex])
                i = data.index(after: optIndex)
            case TelnetIAC.sb:
                i = consumeSubnegotiation(data, from: data.index(after: cmdIndex))
            default:
                i = data.index(after: cmdIndex)
            }
        }
        return decode(output)
    }

    private func handleOption(command: UInt8, option: UInt8) {
        switch command {
        case TelnetIAC.will:
            if option == TelnetIAC.optEcho || option == TelnetIAC.optSGA || option == TelnetIAC.optBinary {
                sendOption(TelnetIAC.do, option)
            } else {
                sendOption(TelnetIAC.dont, option)
            }
        case TelnetIAC.do:
            if option == TelnetIAC.optSGA || option == TelnetIAC.optBinary {
                sendOption(TelnetIAC.will, option)
            } else if option == TelnetIAC.optTType {
                sendOption(TelnetIAC.will, option)
            } else if option == TelnetIAC.optNAWS {
                sendOption(TelnetIAC.will, option)
                sendNAWS()
            } else {
                sendOption(TelnetIAC.wont, option)
            }
        case TelnetIAC.wont, TelnetIAC.dont:
            break
        default:
            break
        }
    }

    private func consumeSubnegotiation(_ data: Data, from start: Data.Index) -> Data.Index {
        var i = start
        var payload = Data()
        while i < data.endIndex {
            if data[i] == TelnetIAC.iac {
                let next = data.index(after: i)
                guard next < data.endIndex else { return data.endIndex }
                if data[next] == TelnetIAC.se {
                    handleSubnegotiation(payload)
                    return data.index(after: next)
                }
                payload.append(data[next])
                i = data.index(after: next)
            } else {
                payload.append(data[i])
                i = data.index(after: i)
            }
        }
        return data.endIndex
    }

    private func handleSubnegotiation(_ payload: Data) {
        guard let option = payload.first else { return }
        if option == TelnetIAC.optTType, payload.count >= 2, payload[payload.index(after: payload.startIndex)] == 1 {
            var reply = Data([TelnetIAC.iac, TelnetIAC.sb, TelnetIAC.optTType, 0])
            reply.append(contentsOf: Array("xterm-256color".utf8))
            reply.append(contentsOf: [TelnetIAC.iac, TelnetIAC.se])
            sendRaw(reply)
        }
    }

    private func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}

private enum TelnetIAC {
    static let iac: UInt8 = 255
    static let dont: UInt8 = 254
    static let `do`: UInt8 = 253
    static let wont: UInt8 = 252
    static let will: UInt8 = 251
    static let sb: UInt8 = 250
    static let ga: UInt8 = 249
    static let el: UInt8 = 248
    static let ec: UInt8 = 247
    static let ayt: UInt8 = 246
    static let ao: UInt8 = 245
    static let ip: UInt8 = 244
    static let brk: UInt8 = 243
    static let dm: UInt8 = 242
    static let nop: UInt8 = 241
    static let se: UInt8 = 240
    static let optBinary: UInt8 = 0
    static let optEcho: UInt8 = 1
    static let optSGA: UInt8 = 3
    static let optTType: UInt8 = 24
    static let optNAWS: UInt8 = 31
}
