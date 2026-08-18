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
            return [.tcpClient, .tcpServer, .udpTool, .serial, .httpClient]
        case .desktop:
            return [.vnc, .rdp]
        case .agentCLI:
            return [.agentCLI]
        }
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
    case vnc = "VNC"
    case rdp = "RDP"
    case agentCLI = "Agent CLI"

    public var id: String { rawValue }

    public var category: SessionCategory {
        switch self {
        case .ssh, .sftp, .telnet:
            return .remote
        case .tcpClient, .tcpServer, .udpTool, .serial, .httpClient:
            return .debug
        case .vnc, .rdp:
            return .desktop
        case .agentCLI:
            return .agentCLI
        }
    }

    public var usesAccountAuth: Bool {
        switch self {
        case .ssh, .sftp, .telnet: return true
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
        case id, name, type, host, port, username, authMethod, accountID, customArgs, workingDirectory, envVars
    }

    public var id: UUID
    public var name: String
    public var type: SessionType
    public var host: String
    public var port: Int
    /// Display snapshot only. SSH credentials come from `accountID`.
    public var username: String
    public var authMethod: SSHAuthMethod
    public var accountID: UUID?
    public var customArgs: String?
    public var workingDirectory: String?
    public var envVars: [String: String]?

    public init(
        id: UUID = UUID(),
        name: String,
        type: SessionType,
        host: String = "127.0.0.1",
        port: Int = 22,
        username: String = "",
        authMethod: SSHAuthMethod = .password,
        accountID: UUID? = nil,
        customArgs: String? = nil,
        workingDirectory: String? = nil,
        envVars: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.accountID = accountID
        self.customArgs = customArgs
        self.workingDirectory = workingDirectory
        self.envVars = envVars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(SessionType.self, forKey: .type)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        authMethod = try c.decodeIfPresent(SSHAuthMethod.self, forKey: .authMethod) ?? .password
        accountID = try c.decodeIfPresent(UUID.self, forKey: .accountID)
        customArgs = try c.decodeIfPresent(String.self, forKey: .customArgs)
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .workingDirectory)
        envVars = try c.decodeIfPresent([String: String].self, forKey: .envVars)
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
    public var targetDevice: String?
    public var customCommand: String?
    public var workingDirectory: String?
    public var environmentVariables: [String: String]?
    public var connectionID: UUID?
    public var accountID: UUID?

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
        targetDevice: String? = nil,
        customCommand: String? = nil,
        workingDirectory: String? = nil,
        environmentVariables: [String: String]? = nil,
        connectionID: UUID? = nil,
        accountID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.isConnected = isConnected
        self.isSuspended = isSuspended
        self.host = host
        self.port = port
        self.targetDevice = targetDevice
        self.customCommand = customCommand
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.connectionID = connectionID
        self.accountID = accountID
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

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: LogDirection,
        content: String,
        hexRepresentation: String? = nil,
        byteCount: Int = 0,
        remoteEndpoint: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.content = content
        self.hexRepresentation = hexRepresentation
        self.byteCount = byteCount
        self.remoteEndpoint = remoteEndpoint
    }
}
