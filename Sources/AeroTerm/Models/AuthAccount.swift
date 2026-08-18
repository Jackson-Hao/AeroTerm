import Foundation

public enum AccountKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ssh
    case telnet
    case vnc
    case rdp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ssh: return "SSH / SFTP"
        case .telnet: return "Telnet"
        case .vnc: return "VNC"
        case .rdp: return "RDP"
        }
    }

    public func supports(_ type: SessionType) -> Bool {
        switch self {
        case .ssh: return type == .ssh || type == .sftp
        case .telnet: return type == .telnet
        case .vnc: return type == .vnc
        case .rdp: return type == .rdp
        }
    }

    public var usesPrivateKey: Bool { self == .ssh }
    public var requiresUsername: Bool { self != .vnc }
    public var requiresSecret: Bool { self == .ssh || self == .vnc || self == .rdp }
}

/// Independent login profile. Secrets live in SecretStore under `id`, not under a connection.
public struct AuthAccount: Identifiable, Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, name, username, authMethod, privateKeyPath, updatedAt, kind
    }

    public var id: UUID
    public var name: String
    public var username: String
    public var kind: AccountKind
    public var authMethod: SSHAuthMethod
    public var privateKeyPath: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        kind: AccountKind = .ssh,
        authMethod: SSHAuthMethod = .password,
        privateKeyPath: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.kind = kind
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        kind = try c.decodeIfPresent(AccountKind.self, forKey: .kind) ?? .ssh
        authMethod = try c.decodeIfPresent(SSHAuthMethod.self, forKey: .authMethod) ?? .password
        privateKeyPath = try c.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    public var pickerLabel: String {
        let user = username.isEmpty ? "—" : username
        return "\(name)  ·  \(user)"
    }

    public var methodLabel: String {
        if kind != .ssh { return kind.displayName }
        return authMethod == .publicKey ? "Private Key" : "Password"
    }
}
