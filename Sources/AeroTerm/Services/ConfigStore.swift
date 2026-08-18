import Foundation

/// JSON configs next to the secret vault: ~/.config/aero/aeroterm/
@MainActor
public final class ConfigStore {
    public static let shared = ConfigStore()

    public static var directoryURL: URL { SecretStore.directoryURL }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        try? FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
    }

    public func loadAccounts() -> [AuthAccount] {
        load("accounts.json") ?? []
    }

    public func saveAccounts(_ items: [AuthAccount]) {
        save(items, as: "accounts.json")
    }

    public func loadConnections() -> [ConnectionConfig] {
        load("connections.json") ?? []
    }

    public func saveConnections(_ items: [ConnectionConfig]) {
        save(items, as: "connections.json")
    }

    public func loadRecents() -> [RecentConnection] {
        load("recents.json") ?? []
    }

    public func saveRecents(_ items: [RecentConnection]) {
        save(items, as: "recents.json")
    }

    public func fileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: Self.directoryURL.appendingPathComponent(name).path)
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        let url = Self.directoryURL.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, as name: String) {
        let url = Self.directoryURL.appendingPathComponent(name)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
