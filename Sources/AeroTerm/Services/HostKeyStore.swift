import Foundation

struct KnownHostRecord: Codable, Equatable, Sendable {
    var host: String
    var port: Int
    var openSSHKey: String
}

/// TOFU store: `~/.config/aero/aeroterm/known_hosts.json`
final class HostKeyStore: @unchecked Sendable {
    static let shared = HostKeyStore()

    private let lock = NSLock()
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    private init() {
        fileURL = ConfigStore.directoryURL.appendingPathComponent("known_hosts.json")
        try? FileManager.default.createDirectory(at: ConfigStore.directoryURL, withIntermediateDirectories: true)
    }

    func verifyOrRemember(host: String, port: Int, openSSHKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var items = loadLocked()
        if let existing = items.first(where: { $0.host == host && $0.port == port }) {
            if existing.openSSHKey != openSSHKey {
                throw SSHConnectError.hostKeyMismatch
            }
            return
        }
        items.append(KnownHostRecord(host: host, port: port, openSSHKey: openSSHKey))
        saveLocked(items)
    }

    private func loadLocked() -> [KnownHostRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([KnownHostRecord].self, from: data)) ?? []
    }

    private func saveLocked(_ items: [KnownHostRecord]) {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
