import Foundation
import SwiftUI

// MARK: - 协议分类枚举 (三大基础分类 + AI & Agent CLI)
public enum SessionCategory: String, CaseIterable, Identifiable, Sendable {
    case remote = "Remote Connection"
    case debug = "Debugging Tools"
    case desktop = "Remote Desktop"
    case agentCLI = "AI & Agent CLI"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .remote: return "network"
        case .debug: return "wrench.and.screwdriver"
        case .desktop: return "display"
        case .agentCLI: return "sparkles"
        }
    }

    public var types: [SessionType] {
        switch self {
        case .remote:
            return [.ssh, .sftp, .telnet]
        case .debug:
            return [.tcpClient, .tcpServer, .udpTool, .serial, .httpClient, .httpServer]
        case .desktop:
            return [.vnc, .rdp]
        case .agentCLI:
            return [.agentCLI]
        }
    }
}

public enum UDPMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case unicast
    case multicast
    case broadcast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unicast: return "Unicast"
        case .multicast: return "Multicast"
        case .broadcast: return "Broadcast"
        }
    }
}

public enum SerialSessionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case shell
    case tester

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .shell: return "serial_mode_shell"
        case .tester: return "serial_mode_tester"
        }
    }

    @MainActor
    public var title: String {
        LocalizationManager.shared.text(titleKey)
    }
}

public enum SerialHighlightStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case linuxUnix
    case keywords
    case syslog
    case atCommand
    case embedded

    public var id: String { rawValue }

    public var titleKey: String { "serial_highlight_\(rawValue)" }
    public var hintKey: String { "serial_highlight_\(rawValue)_hint" }

    @MainActor
    public var title: String {
        LocalizationManager.shared.text(titleKey)
    }
}

public enum SerialDataBits: Int, Codable, CaseIterable, Identifiable, Sendable {
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8

    public var id: Int { rawValue }

    public var title: String { String(rawValue) }
}

public enum SerialParity: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case even
    case odd
    case mark
    case space

    public var id: String { rawValue }

    public var titleKey: String { "serial_parity_\(rawValue)" }

    @MainActor
    public var title: String {
        LocalizationManager.shared.text(titleKey)
    }

    public var code: String {
        switch self {
        case .none: return "N"
        case .even: return "E"
        case .odd: return "O"
        case .mark: return "M"
        case .space: return "S"
        }
    }
}

public enum SerialStopBits: String, Codable, CaseIterable, Identifiable, Sendable {
    case one
    case onePointFive
    case two

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .one: return "1"
        case .onePointFive: return "1.5"
        case .two: return "2"
        }
    }

    public var code: String {
        switch self {
        case .one: return "1"
        case .onePointFive: return "1.5"
        case .two: return "2"
        }
    }
}

public enum SerialFlowControl: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case rtscts
    case xonxoff

    public var id: String { rawValue }

    /// Industry abbreviations (RTS/CTS, XON/XOFF) stay in the string catalog as-is.
    public var titleKey: String { "serial_flow_\(rawValue)" }

    @MainActor
    public var title: String {
        LocalizationManager.shared.text(titleKey)
    }

    public var symbol: String {
        switch self {
        case .none: return ""
        case .rtscts: return "RTS/CTS"
        case .xonxoff: return "XON/XOFF"
        }
    }
}

public struct SerialSettings: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case mode, dataBits, parity, stopBits, flowControl, dtr, rts
        case syntaxHighlight, highlightStyle, colorSchemeID
    }

    public var mode: SerialSessionMode
    public var dataBits: SerialDataBits
    public var parity: SerialParity
    public var stopBits: SerialStopBits
    public var flowControl: SerialFlowControl
    public var dtr: Bool
    public var rts: Bool
    public var highlightStyle: SerialHighlightStyle
    public var colorSchemeID: String

    public static let `default` = SerialSettings()
    public static let wizardDefault = SerialSettings(mode: .shell, highlightStyle: .none)

    public init(
        mode: SerialSessionMode = .tester,
        dataBits: SerialDataBits = .eight,
        parity: SerialParity = .none,
        stopBits: SerialStopBits = .one,
        flowControl: SerialFlowControl = .none,
        dtr: Bool = true,
        rts: Bool = true,
        highlightStyle: SerialHighlightStyle = .none,
        colorSchemeID: String = "follow-app"
    ) {
        self.mode = mode
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
        self.flowControl = flowControl
        self.dtr = dtr
        self.rts = rts
        self.highlightStyle = highlightStyle
        self.colorSchemeID = colorSchemeID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(SerialSessionMode.self, forKey: .mode) ?? .tester
        dataBits = try c.decodeIfPresent(SerialDataBits.self, forKey: .dataBits) ?? .eight
        parity = try c.decodeIfPresent(SerialParity.self, forKey: .parity) ?? .none
        stopBits = try c.decodeIfPresent(SerialStopBits.self, forKey: .stopBits) ?? .one
        flowControl = try c.decodeIfPresent(SerialFlowControl.self, forKey: .flowControl) ?? .none
        dtr = try c.decodeIfPresent(Bool.self, forKey: .dtr) ?? true
        rts = try c.decodeIfPresent(Bool.self, forKey: .rts) ?? true
        if let style = try c.decodeIfPresent(SerialHighlightStyle.self, forKey: .highlightStyle) {
            highlightStyle = style
        } else if let legacy = try c.decodeIfPresent(Bool.self, forKey: .syntaxHighlight) {
            highlightStyle = legacy ? .keywords : .none
        } else {
            highlightStyle = .none
        }
        colorSchemeID = try c.decodeIfPresent(String.self, forKey: .colorSchemeID) ?? "follow-app"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(dataBits, forKey: .dataBits)
        try c.encode(parity, forKey: .parity)
        try c.encode(stopBits, forKey: .stopBits)
        try c.encode(flowControl, forKey: .flowControl)
        try c.encode(dtr, forKey: .dtr)
        try c.encode(rts, forKey: .rts)
        try c.encode(highlightStyle, forKey: .highlightStyle)
        try c.encode(colorSchemeID, forKey: .colorSchemeID)
    }

    public var lineSpec: String {
        "\(dataBits.rawValue)\(parity.code)\(stopBits.code)"
    }

    public var detailLabel: String {
        var parts = [lineSpec]
        if flowControl != .none {
            parts.append(flowControl.symbol)
        }
        return parts.joined(separator: " ")
    }
}

public enum DesktopQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case high
    case balanced
    case low

    public var id: String { rawValue }

    public var titleKey: String { "desktop_quality_\(rawValue)" }

    @MainActor
    public var title: String {
        LocalizationManager.shared.text(titleKey)
    }

    public var vncJpegQuality: Int {
        switch self {
        case .high: return 8
        case .balanced: return 6
        case .low: return 3
        }
    }

    public var vncCompression: Int {
        switch self {
        case .high: return 4
        case .balanced: return 6
        case .low: return 8
        }
    }
}

public enum DesktopRefreshRate: Int, Codable, CaseIterable, Identifiable, Sendable {
    case hz60 = 60
    case hz30 = 30
    case hz15 = 15

    public var id: Int { rawValue }

    public var titleKey: String { "desktop_refresh_\(rawValue)" }

    @MainActor
    public var title: String {
        LocalizationManager.shared.text(titleKey)
    }

    public var frameInterval: TimeInterval {
        1.0 / Double(rawValue)
    }
}

public struct DesktopDisplaySettings: Codable, Equatable, Sendable {
    public var quality: DesktopQuality
    public var refreshRate: DesktopRefreshRate

    public static let `default` = DesktopDisplaySettings(quality: .high, refreshRate: .hz60)

    public init(quality: DesktopQuality = .high, refreshRate: DesktopRefreshRate = .hz60) {
        self.quality = quality
        self.refreshRate = refreshRate
    }
}

public enum SessionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ssh = "SSH"
    case sftp = "SFTP"
    case telnet = "Telnet"
    case tcpClient = "TCP Client"
    case tcpServer = "TCP Server"
    case udpTool = "UDP Tool"
    case serial = "Serial Port"
    case httpClient = "HTTP API"
    case httpServer = "HTTP Server"
    case vnc = "VNC"
    case rdp = "RDP"
    case agentCLI = "Agent CLI"

    public var id: String { rawValue }

    public var category: SessionCategory {
        switch self {
        case .ssh, .sftp, .telnet:
            return .remote
        case .tcpClient, .tcpServer, .udpTool, .serial, .httpClient, .httpServer:
            return .debug
        case .vnc, .rdp:
            return .desktop
        case .agentCLI:
            return .agentCLI
        }
    }

    public var usesAccountAuth: Bool {
        switch self {
        case .ssh, .sftp, .telnet, .vnc, .rdp: return true
        default: return false
        }
    }

    public var usesAccountPicker: Bool {
        switch self {
        case .ssh, .sftp, .telnet, .vnc, .rdp: return true
        default: return false
        }
    }

    public var accountKind: AccountKind {
        switch self {
        case .ssh, .sftp: return .ssh
        case .telnet: return .telnet
        case .vnc: return .vnc
        case .rdp: return .rdp
        default: return .ssh
        }
    }

    public var defaultPort: Int {
        switch self {
        case .ssh, .sftp: return 22
        case .telnet: return 23
        case .tcpClient, .tcpServer, .udpTool: return 8080
        case .serial: return 115200
        case .httpClient: return 80
        case .httpServer: return 8080
        case .vnc: return 5900
        case .rdp: return 3389
        case .agentCLI: return 0
        }
    }

    public var iconName: String {
        switch self {
        case .ssh: return "terminal.fill"
        case .sftp: return "folder.fill.badge.gearshape"
        case .telnet: return "network"
        case .tcpClient: return "arrow.up.right.circle.fill"
        case .tcpServer: return "antenna.radiowaves.left.and.right"
        case .udpTool: return "point.3.filled.connected.trianglepath.dotted"
        case .serial: return "cable.connector"
        case .httpClient: return "globe"
        case .httpServer: return "server.rack"
        case .vnc: return "display"
        case .rdp: return "server.rack"
        case .agentCLI: return "sparkles"
        }
    }

    public var tintColor: Color {
        switch self {
        case .ssh: return .blue
        case .sftp: return .cyan
        case .telnet: return .indigo
        case .tcpClient: return .green
        case .tcpServer: return .teal
        case .udpTool: return .orange
        case .serial: return .purple
        case .httpClient: return .blue
        case .httpServer: return .teal
        case .vnc: return .pink
        case .rdp: return .red
        case .agentCLI: return .purple
        }
    }

    @MainActor
    public var description: String {
        switch self {
        case .ssh:
            return LocalizationManager.shared.text("ssh_desc")
        case .sftp:
            return LocalizationManager.shared.text("sftp_desc")
        case .telnet:
            return LocalizationManager.shared.text("telnet_desc")
        case .tcpClient:
            return LocalizationManager.shared.text("tcp_client_desc")
        case .tcpServer:
            return LocalizationManager.shared.text("tcp_server_desc")
        case .udpTool:
            return LocalizationManager.shared.text("udp_tool_desc")
        case .serial:
            return LocalizationManager.shared.text("serial_desc")
        case .httpClient:
            return LocalizationManager.shared.text("http_client_desc")
        case .httpServer:
            return LocalizationManager.shared.text("http_server_desc")
        case .vnc:
            return LocalizationManager.shared.text("vnc_desc")
        case .rdp:
            return LocalizationManager.shared.text("rdp_desc")
        case .agentCLI:
            return "Launch Claude Code, Codex, Antigravity, Grok, Hermes and custom AI Agents."
        }
    }
}

public struct ConnectionConfig: Identifiable, Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, name, type, host, port, localPort, udpMode, username, authMethod, accountID, customArgs, workingDirectory, envVars, label, serial, desktop
    }

    public var id: UUID
    public var name: String
    public var type: SessionType
    public var host: String
    public var port: Int
    /// Bind / listen port. 0 = system-assigned.
    public var localPort: Int
    public var udpMode: UDPMode
    /// Display snapshot only. SSH credentials come from `accountID`.
    public var username: String
    public var authMethod: SSHAuthMethod
    public var accountID: UUID?
    public var customArgs: String?
    public var workingDirectory: String?
    public var envVars: [String: String]?
    public var label: String
    public var serial: SerialSettings
    public var desktop: DesktopDisplaySettings

    public init(
        id: UUID = UUID(),
        name: String,
        type: SessionType,
        host: String = "127.0.0.1",
        port: Int = 22,
        localPort: Int = 0,
        udpMode: UDPMode = .unicast,
        username: String = "",
        authMethod: SSHAuthMethod = .password,
        accountID: UUID? = nil,
        customArgs: String? = nil,
        workingDirectory: String? = nil,
        envVars: [String: String]? = nil,
        label: String = "",
        serial: SerialSettings = .default,
        desktop: DesktopDisplaySettings = .default
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.localPort = localPort
        self.udpMode = udpMode
        self.username = username
        self.authMethod = authMethod
        self.accountID = accountID
        self.customArgs = customArgs
        self.workingDirectory = workingDirectory
        self.envVars = envVars
        self.label = label
        self.serial = serial
        self.desktop = desktop
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(SessionType.self, forKey: .type)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        localPort = try c.decodeIfPresent(Int.self, forKey: .localPort) ?? 0
        udpMode = try c.decodeIfPresent(UDPMode.self, forKey: .udpMode) ?? .unicast
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        authMethod = try c.decodeIfPresent(SSHAuthMethod.self, forKey: .authMethod) ?? .password
        accountID = try c.decodeIfPresent(UUID.self, forKey: .accountID)
        customArgs = try c.decodeIfPresent(String.self, forKey: .customArgs)
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .workingDirectory)
        envVars = try c.decodeIfPresent([String: String].self, forKey: .envVars)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        serial = try c.decodeIfPresent(SerialSettings.self, forKey: .serial) ?? .default
        desktop = try c.decodeIfPresent(DesktopDisplaySettings.self, forKey: .desktop) ?? .default
    }
}

public struct RecentConnection: Identifiable, Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, title, type, host, port, username, accountID, lastUsed
    }

    public var id: UUID
    public var title: String
    public var type: SessionType
    public var host: String
    public var port: Int
    public var username: String?
    public var accountID: UUID?
    public var lastUsed: Date

    public init(
        id: UUID = UUID(),
        title: String,
        type: SessionType,
        host: String,
        port: Int,
        username: String? = nil,
        accountID: UUID? = nil,
        lastUsed: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.host = host
        self.port = port
        self.username = username
        self.accountID = accountID
        self.lastUsed = lastUsed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        type = try c.decode(SessionType.self, forKey: .type)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        accountID = try c.decodeIfPresent(UUID.self, forKey: .accountID)
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? Date()
    }
}

public struct SessionItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var subtitle: String
    public var type: SessionType
    public var isConnected: Bool
    public var isSuspended: Bool
    public var host: String
    public var port: Int
    public var localPort: Int
    public var udpMode: UDPMode
    public var targetDevice: String?
    public var customCommand: String?
    public var workingDirectory: String?
    public var environmentVariables: [String: String]?
    public var connectionID: UUID?
    public var accountID: UUID?
    public var label: String
    public var serial: SerialSettings
    public var desktop: DesktopDisplaySettings

    public var indicatorColor: Color {
        if isSuspended { return .yellow }
        return isConnected ? .green : .yellow
    }

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        type: SessionType,
        isConnected: Bool = false,
        isSuspended: Bool = false,
        host: String = "",
        port: Int = 0,
        localPort: Int = 0,
        udpMode: UDPMode = .unicast,
        targetDevice: String? = nil,
        customCommand: String? = nil,
        workingDirectory: String? = nil,
        environmentVariables: [String: String]? = nil,
        connectionID: UUID? = nil,
        accountID: UUID? = nil,
        label: String = "",
        serial: SerialSettings = .default,
        desktop: DesktopDisplaySettings = .default
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.isConnected = isConnected
        self.isSuspended = isSuspended
        self.host = host
        self.port = port
        self.localPort = localPort
        self.udpMode = udpMode
        self.targetDevice = targetDevice
        self.customCommand = customCommand
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.connectionID = connectionID
        self.accountID = accountID
        self.label = label
        self.serial = serial
        self.desktop = desktop
    }
}

// MARK: - 网络日志模型
public enum LogDirection: String, Codable, Sendable {
    case send = "TX"
    case receive = "RX"
    case system = "SYS"
    case error = "ERR"

    public var color: Color {
        switch self {
        case .send: return .blue
        case .receive: return .green
        case .system: return .secondary
        case .error: return .red
        }
    }
}

public struct NetworkLogItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let direction: LogDirection
    public let content: String
    public let hexRepresentation: String?
    public let byteCount: Int
    public let remoteEndpoint: String?
    public let payload: Data?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: LogDirection,
        content: String,
        hexRepresentation: String? = nil,
        byteCount: Int = 0,
        remoteEndpoint: String? = nil,
        payload: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.content = content
        self.hexRepresentation = hexRepresentation
        self.byteCount = byteCount
        self.remoteEndpoint = remoteEndpoint
        self.payload = payload
    }
}
