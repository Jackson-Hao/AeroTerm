import Foundation
import AppKit
import SwiftUI
import SwiftTerm
import Combine
@preconcurrency import Citadel
import NIOCore
import NIOSSH

enum SSHKeepAlive {
    static let intervalNanoseconds: UInt64 = 30_000_000_000
}

@MainActor
public final class SSHTerminalSession: ObservableObject {
    public let client: SSHClient
    public let sessionID: UUID
    public let terminalView: TerminalView

    @Published public var isAlive: Bool = true

    private let engine: SSHPTYEngine
    private var themeSignature = ""

    public init(client: SSHClient, sessionID: UUID) {
        self.client = client
        self.sessionID = sessionID
        let view = TerminalView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        view.focusRingType = .none
        self.terminalView = view
        self.engine = SSHPTYEngine(client: client, sessionID: sessionID, terminalView: view)
        view.terminalDelegate = engine
        applyTheme()
        client.onDisconnect { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect()
            }
        }
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
        try? await client.close()
        isAlive = false
    }

    func handleDisconnect() {
        guard isAlive else { return }
        isAlive = false
        SessionManager.shared.markSessionDisconnected(id: sessionID)
    }

    private func startKeepAlive() {
        let client = self.client
        engine.keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: SSHKeepAlive.intervalNanoseconds)
                guard !Task.isCancelled else { return }
                if !client.isConnected {
                    await MainActor.run { self?.handleDisconnect() }
                    return
                }
            }
        }
    }
}

final class SSHPTYEngine: TerminalViewDelegate, @unchecked Sendable {
    enum Event {
        case send(ByteBuffer)
        case changeSize(cols: Int, rows: Int)
    }

    let client: SSHClient
    let sessionID: UUID
    weak var terminalView: TerminalView?
    private let events = AsyncStream<Event>.makeStream()
    private var ptyTask: Task<Void, Never>?
    var keepAliveTask: Task<Void, Never>?
    private var started = false
    private var finished = false

    init(client: SSHClient, sessionID: UUID, terminalView: TerminalView) {
        self.client = client
        self.sessionID = sessionID
        self.terminalView = terminalView
    }

    func start() {
        guard !started else { return }
        started = true
        ptyTask = Task { [weak self] in
            await self?.runPTY()
        }
    }

    func finish() {
        finished = true
        keepAliveTask?.cancel()
        keepAliveTask = nil
        ptyTask?.cancel()
        events.continuation.finish()
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard !finished, newCols >= 10, newRows >= 5 else { return }
        events.continuation.yield(.changeSize(cols: newCols, rows: newRows))
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !finished else { return }
        events.continuation.yield(.send(ByteBuffer(bytes: data)))
    }

    private func runPTY() async {
        do {
            try await client.withPTY(
                SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: 80,
                    terminalRowHeight: 24,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([.ECHO: 1])
                )
            ) { [events = events.stream] inbound, outbound in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await input in inbound {
                            switch input {
                            case .stdout(var buffer), .stderr(var buffer):
                                let bytes = buffer.readBytes(length: buffer.readableBytes)?[...] ?? []
                                await MainActor.run {
                                    self.terminalView?.feed(byteArray: bytes)
                                }
                            }
                        }
                    }
                    group.addTask {
                        for try await event in events {
                            switch event {
                            case .send(let buffer):
                                try await outbound.write(buffer)
                            case .changeSize(let cols, let rows):
                                try await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
                            }
                        }
                    }
                    _ = try await group.next()
                    group.cancelAll()
                }
            }
        } catch {
            await MainActor.run {
                self.terminalView?.feed(text: "\r\nSession ended: \(error.localizedDescription)\r\n")
            }
        }

        let id = sessionID
        let shouldMarkDisconnected = !finished
        await MainActor.run {
            if shouldMarkDisconnected {
                SessionManager.shared.sshSessions[id]?.handleDisconnect()
            }
        }
    }
}
