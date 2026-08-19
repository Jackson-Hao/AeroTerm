import Foundation
import CryptoKit
import Security
import SQLite3

public enum SecretKind: String, Sendable {
    case password
    case privateKey
    case keyPassphrase
}

public enum SSHAuthMethod: String, Codable, Sendable {
    case password
    case publicKey
}

/// Encrypted SQLite vault for SSH passwords and private keys.
/// Database: ~/.config/aero/aeroterm/secrets.sqlite
/// Master key lives in the login Keychain; access is required before splash.
@MainActor
public final class SecretStore {
    public static let shared = SecretStore()

    nonisolated public static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aero/aeroterm", isDirectory: true)
    }

    private var db: OpaquePointer?
    private var masterKey: SymmetricKey?

    public var isUnlocked: Bool { masterKey != nil }

    private init() {
        Self.ensureDirectory()
    }

    /// Read or create the Keychain master key. Denied / cancelled → false.
    @discardableResult
    public func unlock() -> Bool {
        if masterKey != nil { return true }

        switch Self.readKeychain() {
        case .success(let data):
            return finishUnlock(data)
        case .denied:
            return false
        case .notFound:
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let data = Data(bytes)
            let added = Self.addKeychain(data)
            if added == errSecSuccess {
                return finishUnlock(data)
            }
            if added == errSecDuplicateItem {
                if case .success(let existing) = Self.readKeychain() {
                    return finishUnlock(existing)
                }
            }
            return false
        }
    }

    private func finishUnlock(_ data: Data) -> Bool {
        masterKey = SymmetricKey(data: data)
        Self.removeLegacyMasterKeyFile()
        db = Self.openDatabase()
        guard db != nil else {
            masterKey = nil
            return false
        }
        Self.createSchema(db)
        return true
    }

    public func set(_ kind: SecretKind, accountID: UUID, plaintext: String?) {
        guard isUnlocked else { return }
        guard let plaintext, !plaintext.isEmpty else {
            delete(kind, accountID: accountID)
            return
        }
        guard let sealed = try? encrypt(plaintext) else { return }
        let sql = """
            INSERT INTO secrets(account_id, kind, nonce, ciphertext, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(account_id, kind) DO UPDATE SET
                nonce = excluded.nonce,
                ciphertext = excluded.ciphertext,
                updated_at = excluded.updated_at;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindOwner(stmt, accountID: accountID, kind: kind)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sealed.nonce.withUnsafeBytes { ptr in
            _ = sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(sealed.nonce.count), transient)
        }
        sealed.ciphertext.withUnsafeBytes { ptr in
            _ = sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(sealed.ciphertext.count), transient)
        }
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    public func get(_ kind: SecretKind, accountID: UUID) -> String? {
        guard isUnlocked else { return nil }
        let sql = "SELECT nonce, ciphertext FROM secrets WHERE account_id = ? AND kind = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindOwner(stmt, accountID: accountID, kind: kind)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let noncePtr = sqlite3_column_blob(stmt, 0),
              let cipherPtr = sqlite3_column_blob(stmt, 1) else { return nil }
        let nonce = Data(bytes: noncePtr, count: Int(sqlite3_column_bytes(stmt, 0)))
        let ciphertext = Data(bytes: cipherPtr, count: Int(sqlite3_column_bytes(stmt, 1)))
        return try? decrypt(nonce: nonce, ciphertext: ciphertext)
    }

    public func hasAnySecret(accountID: UUID) -> Bool {
        get(.password, accountID: accountID) != nil || get(.privateKey, accountID: accountID) != nil
    }

    public func delete(_ kind: SecretKind, accountID: UUID) {
        guard isUnlocked else { return }
        let sql = "DELETE FROM secrets WHERE account_id = ? AND kind = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindOwner(stmt, accountID: accountID, kind: kind)
        sqlite3_step(stmt)
    }

    public func deleteAll(accountID: UUID) {
        guard isUnlocked else { return }
        let sql = "DELETE FROM secrets WHERE account_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let cid = accountID.uuidString as NSString
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, cid.utf8String, -1, transient)
        sqlite3_step(stmt)
    }

    private func bindOwner(_ stmt: OpaquePointer?, accountID: UUID, kind: SecretKind) {
        let cid = accountID.uuidString as NSString
        let kindNS = kind.rawValue as NSString
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, cid.utf8String, -1, transient)
        sqlite3_bind_text(stmt, 2, kindNS.utf8String, -1, transient)
    }

    // MARK: - Crypto

    private struct SealedBlob {
        let nonce: Data
        let ciphertext: Data
    }

    private func encrypt(_ plaintext: String) throws -> SealedBlob {
        guard let masterKey else { throw CocoaError(.userCancelled) }
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: masterKey, nonce: nonce)
        return SealedBlob(nonce: Data(nonce), ciphertext: box.ciphertext + box.tag)
    }

    private func decrypt(nonce: Data, ciphertext: Data) throws -> String {
        guard let masterKey else { throw CocoaError(.userCancelled) }
        let nonce = try AES.GCM.Nonce(data: nonce)
        guard ciphertext.count > 16 else { throw CocoaError(.fileReadCorruptFile) }
        let tag = ciphertext.suffix(16)
        let body = ciphertext.dropLast(16)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        let data = try AES.GCM.open(box, using: masterKey)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Keychain master key

    private static let keychainService = "com.aeroterm.app"
    private static let keychainAccount = "secrets.master-key"

    private enum KeychainRead {
        case success(Data)
        case notFound
        case denied
    }

    private static func readKeychain() -> KeychainRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return .success(data)
        }
        if status == errSecItemNotFound {
            return .notFound
        }
        return .denied
    }

    private static func addKeychain(_ data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }

    private static var masterKeyURL: URL {
        directoryURL.appendingPathComponent("master.key")
    }

    /// Older builds wrote the AES key next to secrets.sqlite. The key lives in Keychain only.
    private static func removeLegacyMasterKeyFile() {
        try? FileManager.default.removeItem(at: masterKeyURL)
    }

    // MARK: - SQLite

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func openDatabase() -> OpaquePointer? {
        let url = directoryURL.appendingPathComponent("secrets.sqlite")
        var handle: OpaquePointer?
        if sqlite3_open(url.path, &handle) != SQLITE_OK {
            return nil
        }
        return handle
    }

    private static func createSchema(_ db: OpaquePointer?) {
        migrateLegacyOwnerColumn(db)
        let sql = """
            CREATE TABLE IF NOT EXISTS secrets (
                account_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                nonce BLOB NOT NULL,
                ciphertext BLOB NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (account_id, kind)
            );
            """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static func migrateLegacyOwnerColumn(_ db: OpaquePointer?) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(secrets);", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        var columns: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                columns.append(String(cString: name))
            }
        }
        guard columns.contains("connection_id"), !columns.contains("account_id") else { return }
        sqlite3_exec(db, "ALTER TABLE secrets RENAME COLUMN connection_id TO account_id;", nil, nil, nil)
    }
}
