import AppKit
import Combine
import SwiftTerm
import SwiftUI

@MainActor
public final class SerialTerminalSession: ObservableObject {
    public let sessionID: UUID
    public let terminalView: TerminalView
    public let engine: SerialEngine

    @Published public var isAlive: Bool = true
    @Published public var highlightStyle: SerialHighlightStyle
    @Published public var colorSchemeID: String

    private var themeSignature = ""
    private var started = false
    private let bridge: SerialTerminalBridge
    private var typedLine = ""
    private var incomingLine = Data()
    private var incomingEscape = Data()
    private var incomingState = IncomingState.text
    private var sawCarriageReturn = false
    private var lineFlushTask: Task<Void, Never>?

    private enum IncomingState {
        case text
        case escape
        case csi
        case osc
    }

    public init(engine: SerialEngine, sessionID: UUID, settings: SerialSettings) {
        self.sessionID = sessionID
        self.engine = engine
        self.highlightStyle = settings.highlightStyle
        self.colorSchemeID = settings.colorSchemeID
        let view = TerminalView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        view.focusRingType = .none
        self.terminalView = view
        let bridge = SerialTerminalBridge()
        self.bridge = bridge
        view.terminalDelegate = bridge
        applyTheme()
        engine.onRawBytes = { [weak self] data in
            Task { @MainActor in
                self?.feed(data)
            }
        }
        engine.onDisconnected = { [weak self] message in
            Task { @MainActor in
                self?.announceDisconnect(message)
            }
        }
        bridge.onSend = { [weak self] bytes in
            Task { @MainActor in
                self?.send(bytes)
            }
        }
    }

    public func start() {
        started = true
        applyTheme()
    }

    public func attach(to container: NSView) {
        if let host = container as? TerminalHostView {
            host.install(terminalView)
        } else {
            resolvedPalette.paint(container)
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

    private var resolvedPalette: SerialColorScheme {
        let schemeID = colorSchemeID == SerialColorScheme.followAppID
            ? SettingsManager.shared.terminalPaletteID
            : colorSchemeID
        return SerialColorScheme.named(schemeID)
    }

    public func applyTheme() {
        let scheme = resolvedPalette
        let signature = "\(scheme.id)|\(TerminalAppearance.signature)|\(highlightStyle.rawValue)"
        guard signature != themeSignature else { return }
        themeSignature = signature
        scheme.apply(to: terminalView)
        if let host = terminalView.superview {
            scheme.paint(host)
        }
    }

    public func updateAppearance(highlightStyle: SerialHighlightStyle, colorSchemeID: String) {
        self.highlightStyle = highlightStyle
        self.colorSchemeID = colorSchemeID
        themeSignature = ""
        applyTheme()
    }

    public func send(_ data: ArraySlice<UInt8>) {
        var localCommand: String?
        for byte in data {
            if byte == 0x0D || byte == 0x0A {
                localCommand = typedLine
                typedLine = ""
            } else if byte == 0x08 || byte == 0x7F {
                if !typedLine.isEmpty { typedLine.removeLast() }
            } else if byte == 0x03 || byte == 0x15 {
                typedLine = ""
            } else if (32..<127).contains(byte) {
                typedLine.append(Character(UnicodeScalar(byte)))
            }
        }
        engine.send(data: Data(data))
        if let localCommand {
            applyLocalShellCommand(localCommand)
        }
    }

    public func shutdown() {
        isAlive = false
        lineFlushTask?.cancel()
        engine.onRawBytes = nil
        engine.onDisconnected = nil
        bridge.onSend = nil
        engine.closePort()
    }

    private func announceDisconnect(_ message: String) {
        terminalView.feed(text: "\r\n\u{1B}[31m*** \(message) ***\u{1B}[0m\r\n")
    }

    private func applyLocalShellCommand(_ raw: String) {
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let first = parts.first, !first.isEmpty else { return }
        let name = (first as NSString).lastPathComponent.lowercased()
        switch name {
        case "clear", "cls":
            applyLocalClear()
        case "reset":
            applyLocalReset()
        case "tput" where parts.dropFirst().first?.lowercased() == "clear":
            applyLocalClear()
        default:
            break
        }
    }

    public func clearScreen() {
        applyLocalClear()
    }

    public func exportedText() -> String {
        let data = terminalView.getTerminal().getBufferAsData()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func applyLocalClear() {
        terminalView.feed(text: "\u{1B}[H\u{1B}[2J\u{1B}[3J")
        terminalView.clearScrollback()
    }

    private func applyLocalReset() {
        terminalView.getTerminal().resetToInitialState()
        terminalView.clearScrollback()
        themeSignature = ""
        applyTheme()
    }

    /// Feed a VT stream. Control/CSI goes through immediately; printable text is
    /// highlighted as a whole line so keywords/paths are not split across chunks.
    private func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        if highlightStyle == .none {
            terminalView.feed(byteArray: ArraySlice([UInt8](data)))
            return
        }
        for byte in data {
            consumeHighlighted(byte)
        }
        scheduleLineFlush()
    }

    private func consumeHighlighted(_ byte: UInt8) {
        switch incomingState {
        case .text:
            if byte == 0x1B {
                flushIncomingLine(fullLine: false)
                incomingEscape = Data([byte])
                incomingState = .escape
                return
            }
            if byte == 0x0D {
                sawCarriageReturn = true
                flushIncomingLine(fullLine: true)
                terminalView.feed(byteArray: [0x0D])
                return
            }
            if byte == 0x0A {
                if !sawCarriageReturn {
                    flushIncomingLine(fullLine: true)
                }
                sawCarriageReturn = false
                terminalView.feed(byteArray: [0x0A])
                return
            }
            sawCarriageReturn = false
            if byte < 0x20 || byte == 0x7F {
                flushIncomingLine(fullLine: false)
                terminalView.feed(byteArray: [byte])
                return
            }
            incomingLine.append(byte)
        case .escape:
            incomingEscape.append(byte)
            if byte == UInt8(ascii: "[") {
                incomingState = .csi
            } else if byte == UInt8(ascii: "]") {
                incomingState = .osc
            } else {
                flushIncomingEscape()
                incomingState = .text
            }
        case .csi:
            incomingEscape.append(byte)
            if (0x40...0x7E).contains(byte) {
                flushIncomingEscape()
                incomingState = .text
            }
        case .osc:
            incomingEscape.append(byte)
            if byte == 0x07 {
                flushIncomingEscape()
                incomingState = .text
            } else if byte == UInt8(ascii: "\\"), incomingEscape.count >= 2,
                      incomingEscape[incomingEscape.count - 2] == 0x1B {
                flushIncomingEscape()
                incomingState = .text
            }
        }
    }

    private func flushIncomingEscape() {
        guard !incomingEscape.isEmpty else { return }
        terminalView.feed(byteArray: ArraySlice([UInt8](incomingEscape)))
        incomingEscape.removeAll(keepingCapacity: true)
    }

    private func flushIncomingLine(fullLine: Bool) {
        lineFlushTask?.cancel()
        lineFlushTask = nil
        guard !incomingLine.isEmpty else { return }
        let rendered = SerialHighlighter.apply(
            highlightStyle,
            to: String(decoding: incomingLine, as: UTF8.self),
            fullLine: fullLine
        )
        terminalView.feed(text: rendered)
        incomingLine.removeAll(keepingCapacity: true)
    }

    private func scheduleLineFlush() {
        guard incomingState == .text, !incomingLine.isEmpty else { return }
        lineFlushTask?.cancel()
        lineFlushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self.flushIncomingLine(fullLine: true)
        }
    }
}

/// TerminalViewDelegate is not isolated to MainActor; this bridge hops send events back.
final class SerialTerminalBridge: TerminalViewDelegate, @unchecked Sendable {
    var onSend: ((ArraySlice<UInt8>) -> Void)?

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let snapshot = Data(data)
        onSend?(ArraySlice(snapshot))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
