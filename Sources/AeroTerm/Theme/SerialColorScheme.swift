import AppKit
import SwiftUI
import SwiftTerm

public struct SerialColorScheme: Identifiable, Equatable, Sendable {
    public static let followAppID = "follow-app"

    public let id: String
    public let nameKey: String
    public let background: String
    public let foreground: String
    public let cursor: String
    public let palette: [String]

    public static let all: [SerialColorScheme] = [
        SerialColorScheme(
            id: followAppID,
            nameKey: "serial_palette_follow_app",
            background: "",
            foreground: "",
            cursor: "",
            palette: []
        ),
        SerialColorScheme(
            id: "aero-dark",
            nameKey: "serial_palette_aero_dark",
            background: "#0B0D11",
            foreground: "#F1F5F9",
            cursor: "#38BDF8",
            palette: [
                "#0F172A", "#F87171", "#4ADE80", "#FBBF24",
                "#60A5FA", "#C084FC", "#38BDF8", "#F8FAFC",
                "#334155", "#FCA5A5", "#86EFAC", "#FDE68A",
                "#93C5FD", "#D8B4FE", "#7DD3FC", "#FFFFFF"
            ]
        ),
        SerialColorScheme(
            id: "aero-light",
            nameKey: "serial_palette_aero_light",
            background: "#F8FAFC",
            foreground: "#0F172A",
            cursor: "#0284C7",
            palette: [
                "#1E293B", "#DC2626", "#16A34A", "#D97706",
                "#2563EB", "#9333EA", "#0891B2", "#F8FAFC",
                "#475569", "#EF4444", "#22C55E", "#F59E0B",
                "#3B82F6", "#A855F7", "#06B6D4", "#FFFFFF"
            ]
        ),
        SerialColorScheme(
            id: "campbell",
            nameKey: "serial_palette_campbell",
            background: "#0C0C0C",
            foreground: "#CCCCCC",
            cursor: "#FFFFFF",
            palette: [
                "#0C0C0C", "#C50F1F", "#13A10E", "#C19C00",
                "#0037DA", "#881798", "#3A96DD", "#CCCCCC",
                "#767676", "#E74856", "#16C60C", "#F9F1A5",
                "#3B78FF", "#B4009E", "#61D6D6", "#F2F2F2"
            ]
        ),
        SerialColorScheme(
            id: "solarized-dark",
            nameKey: "serial_palette_solarized_dark",
            background: "#002B36",
            foreground: "#839496",
            cursor: "#93A1A1",
            palette: [
                "#073642", "#DC322F", "#859900", "#B58900",
                "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                "#002B36", "#CB4B16", "#586E75", "#657B83",
                "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"
            ]
        ),
        SerialColorScheme(
            id: "one-dark",
            nameKey: "serial_palette_one_dark",
            background: "#282C34",
            foreground: "#ABB2BF",
            cursor: "#528BFF",
            palette: [
                "#282C34", "#E06C75", "#98C379", "#E5C07B",
                "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF",
                "#5C6370", "#BE5046", "#98C379", "#D19A66",
                "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF"
            ]
        ),
        SerialColorScheme(
            id: "green",
            nameKey: "serial_palette_green",
            background: "#03140A",
            foreground: "#33FF66",
            cursor: "#66FF99",
            palette: [
                "#03140A", "#FF5A5A", "#33FF66", "#C8FF4A",
                "#3D9EFF", "#C07CFF", "#2EE6C7", "#A8FFBF",
                "#0A2A16", "#FF8A8A", "#6CFF90", "#E4FF86",
                "#7CBCFF", "#D9A6FF", "#6FF0D6", "#E8FFE8"
            ]
        )
    ]

    public static func named(_ id: String) -> SerialColorScheme {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    @MainActor
    public func apply(to terminalView: TerminalView) {
        let resolved = resolvedColors()
        terminalView.nativeBackgroundColor = resolved.background
        terminalView.nativeForegroundColor = resolved.foreground
        terminalView.caretColor = resolved.cursor
        terminalView.installColors(resolved.ansi)
        terminalView.focusRingType = .none
        terminalView.disableFullRedrawOnAnyChanges = true
        terminalView.font = TerminalAppearance.resolvedFont()
    }

    @MainActor
    public var resolvedBackground: NSColor {
        resolvedColors().background
    }

    @MainActor
    public func paint(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = resolvedBackground.cgColor
    }

    @MainActor
    private func resolvedColors() -> (background: NSColor, foreground: NSColor, cursor: NSColor, ansi: [SwiftTerm.Color]) {
        if id == Self.followAppID {
            let theme = ThemeManager.shared.currentTheme
            let palette = theme.palette
            let hexes = [
                palette.black, palette.red, palette.green, palette.yellow,
                palette.blue, palette.magenta, palette.cyan, palette.white
            ]
            let bright = hexes.map { Self.brighten($0) }
            return (
                NSColor(theme.bg),
                NSColor(theme.textPrimary),
                NSColor(theme.accent),
                (hexes + bright).map { Self.swiftTermColor($0) }
            )
        }
        return (
            Self.nsColor(background),
            Self.nsColor(foreground),
            Self.nsColor(cursor),
            palette.map { Self.swiftTermColor($0) }
        )
    }

    private static func nsColor(_ hex: String) -> NSColor {
        let rgb = rgb(hex)
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    private static func swiftTermColor(_ hex: String) -> SwiftTerm.Color {
        let rgb = rgb(hex)
        return SwiftTerm.Color(
            red8: UInt16(rgb.0 * 255),
            green8: UInt16(rgb.1 * 255),
            blue8: UInt16(rgb.2 * 255)
        )
    }

    private static func brighten(_ hex: String) -> String {
        let rgb = rgb(hex)
        let lift: (Double) -> Double = { min(1, $0 + (1 - $0) * 0.28) }
        return String(
            format: "#%02X%02X%02X",
            Int(lift(rgb.0) * 255),
            Int(lift(rgb.1) * 255),
            Int(lift(rgb.2) * 255)
        )
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8:
            (r, g, b) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        return (Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }
}

enum SerialANSI {
    static func strip(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out = Data()
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x1B {
                i += 1
                guard i < bytes.count else { break }
                switch bytes[i] {
                case UInt8(ascii: "["):
                    i += 1
                    while i < bytes.count, !(0x40...0x7E).contains(bytes[i]) { i += 1 }
                    if i < bytes.count { i += 1 }
                case UInt8(ascii: "]"):
                    i += 1
                    while i < bytes.count {
                        if bytes[i] == 0x07 {
                            i += 1
                            break
                        }
                        if bytes[i] == 0x1B {
                            i += 1
                            if i < bytes.count, bytes[i] == UInt8(ascii: "\\") { i += 1 }
                            break
                        }
                        i += 1
                    }
                case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"):
                    i += 1
                    if i < bytes.count { i += 1 }
                default:
                    i += 1
                }
                continue
            }
            out.append(bytes[i])
            i += 1
        }
        return out
    }

    static func visibleText(_ data: Data, decode: (Data) -> String) -> String {
        stripResidues(HexUtils.sanitizedText(decode(strip(data))))
    }

    /// `ls --color` leftovers after ESC was dropped: `[0;0m`, `[01;34m`, `[m`.
    static func stripResidues(_ text: String) -> String {
        guard let regex = residueRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static let residueRegex = try? NSRegularExpression(
        pattern: #"\[[\d;?]{0,24}[mKHfJABCDhl]"#
    )
}

enum SerialHighlighter {
    static func apply(_ style: SerialHighlightStyle, to text: String, fullLine: Bool = true) -> String {
        guard !text.isEmpty, style != .none else { return text }
        let token = tokenRules(for: style)
        let line = fullLine ? lineRules(for: style) : []
        if !text.unicodeScalars.contains(where: { $0.value == 0x1B }) {
            return paint(paint(text, line), token)
        }
        return splitANSI(text).map { part in
            part.isEscape ? part.text : paint(part.text, token)
        }.joined()
    }

    private static func tokenRules(for style: SerialHighlightStyle) -> [(String, String)] {
        switch style {
        case .none:
            return []
        case .linuxUnix:
            return linuxUnixTokenRules + keywordRules
        case .keywords:
            return keywordRules
        case .syslog:
            return syslogRules
        case .atCommand:
            return atCommandRules
        case .embedded:
            return embeddedRules
        }
    }

    private static func lineRules(for style: SerialHighlightStyle) -> [(String, String)] {
        switch style {
        case .linuxUnix:
            return linuxUnixLineRules
        case .embedded:
            return [(#"^([EWIDV]\s*\(\d+\))"#, "36")]
        default:
            return []
        }
    }

    private static func paint(_ text: String, _ rules: [(String, String)]) -> String {
        guard !text.isEmpty, !rules.isEmpty else { return text }
        var result = text
        for (pattern, code) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "\u{1B}[\(code)m$1\u{1B}[0m"
            )
        }
        return result
    }

    private struct ANSIPart {
        let text: String
        let isEscape: Bool
    }

    private static func splitANSI(_ text: String) -> [ANSIPart] {
        var parts: [ANSIPart] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\u{1B}" {
                if !current.isEmpty {
                    parts.append(ANSIPart(text: current, isEscape: false))
                    current = ""
                }
                var end = text.index(after: index)
                if end < text.endIndex, text[end] == "[" {
                    end = text.index(after: end)
                    while end < text.endIndex {
                        let scalar = text[end]
                        end = text.index(after: end)
                        if let ascii = scalar.asciiValue, (0x40...0x7E).contains(ascii) { break }
                    }
                } else if end < text.endIndex {
                    end = text.index(after: end)
                }
                parts.append(ANSIPart(text: String(text[index..<end]), isEscape: true))
                index = end
            } else {
                current.append(text[index])
                index = text.index(after: index)
            }
        }
        if !current.isEmpty {
            parts.append(ANSIPart(text: current, isEscape: false))
        }
        return parts
    }

    private static let linuxUnixLineRules: [(String, String)] = [
        (#"^((?:login|Password|Last login)[: ].*)$"#, "36"),
        (#"([#\$]\s*$)"#, "33")
    ]

    private static let linuxUnixTokenRules: [(String, String)] = [
        (#"(Permission denied|No such file or directory|command not found|Operation not permitted|Connection refused|No route to host)"#, "31"),
        (#"(\[\s*FAILED\s*\])"#, "31"),
        (#"(\[\s*OK\s*\])"#, "32"),
        (#"(\b(?:Call Trace|Oops|BUG|kernel BUG|panic)\b)"#, "31"),
        (#"(\b[dlcbps-](?:[r-][w-][xXsStT-]){9}\b)"#, "35"),
        (#"(\b\d{1,3}(?:\.\d{1,3}){3}\b)"#, "36"),
        (#"(\/[A-Za-z0-9._+-]+(?:\/[A-Za-z0-9._+-]+)*)"#, "34"),
        (#"([A-Za-z0-9._-]+@[A-Za-z0-9._-]+)"#, "32"),
        (#"((?:root|ubuntu|pi|admin)@)"#, "31"),
        (#"(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')"#, "33")
    ]

    private static let keywordRules: [(String, String)] = [
        (#"\b(ERROR|ERR|FATAL|FAIL(?:ED|URE)?|CRITICAL|EXCEPTION|PANIC)\b"#, "31"),
        (#"\b(WARN(?:ING)?)\b"#, "33"),
        (#"\b(INFO|DEBUG|TRACE|NOTICE)\b"#, "36"),
        (#"\b(OK|PASS|SUCCESS)\b"#, "32")
    ]

    private static let syslogRules: [(String, String)] = [
        (#"\b(emerg(?:ency)?|alert|crit(?:ical)?|err(?:or)?)\b"#, "31"),
        (#"\b(warn(?:ing)?)\b"#, "33"),
        (#"\b(notice|info|debug)\b"#, "36"),
        (#"(<(?:[0-3])>)"#, "31"),
        (#"(<(?:[4-5])>)"#, "33"),
        (#"(<(?:[6-7])>)"#, "36"),
        (#"((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})"#, "37")
    ]

    private static let atCommandRules: [(String, String)] = [
        (#"\b(ERROR|NO CARRIER|BUSY|NO ANSWER|NO DIALTONE|\+CME ERROR|\+CMS ERROR)\b"#, "31"),
        (#"\b(OK|CONNECT|RING|RDY|READY)\b"#, "32"),
        (#"(\+[A-Z][A-Z0-9]*:)"#, "33"),
        (#"\b(AT[+&]?[A-Z0-9]*)\b"#, "36")
    ]

    private static let embeddedRules: [(String, String)] = [
        (#"\b(ASSERT|HardFault|UsageFault|BusFault|MemManage|panic)\b"#, "31"),
        (#"\b(ERROR|FAIL|FAULT|TIMEOUT)\b"#, "31"),
        (#"\b(WARN(?:ING)?)\b"#, "33"),
        (#"\b(OK|PASS|SUCCESS)\b"#, "32"),
        (#"(\[[EWID]\])"#, "33"),
        (#"\b(0x[0-9A-Fa-f]+)\b"#, "35")
    ]
}
