import Foundation
import Citadel
import NIOCore
import NIOSSH
import Crypto
import Network
import SwiftTerm

public enum SSHAuthBuilder {
    public static func makeMethod(
        username: String,
        authMethod: SSHAuthMethod,
        password: String?,
        privateKeyPEM: String?,
        keyPassphrase: String?
    ) throws -> SSHAuthenticationMethod {
        switch authMethod {
        case .publicKey:
            guard let pem = privateKeyPEM, !pem.isEmpty else {
                throw SSHConnectError.missingCredentials
            }
            return try makeMethod(
                username: username,
                password: nil,
                privateKeyPEM: pem,
                keyPassphrase: keyPassphrase
            )
        case .password:
            return try makeMethod(
                username: username,
                password: password,
                privateKeyPEM: nil,
                keyPassphrase: nil
            )
        }
    }

    public static func makeMethod(
        username: String,
        password: String?,
        privateKeyPEM: String?,
        keyPassphrase: String?
    ) throws -> SSHAuthenticationMethod {
        let user = username.isEmpty ? NSUserName() : username
        if let pem = privateKeyPEM, !pem.isEmpty {
            let decrypt = keyPassphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
            if pem.contains("BEGIN OPENSSH PRIVATE KEY") || pem.contains("BEGIN RSA PRIVATE KEY") {
                if let type = try? SSHKeyDetection.detectPrivateKeyType(from: pem) {
                    switch type {
                    case .ed25519:
                        let key = try Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decrypt)
                        return .ed25519(username: user, privateKey: key)
                    case .rsa:
                        let key = try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decrypt)
                        return .rsa(username: user, privateKey: key)
                    default:
                        break
                    }
                }
                if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decrypt) {
                    return .ed25519(username: user, privateKey: key)
                }
                if let key = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decrypt) {
                    return .rsa(username: user, privateKey: key)
                }
            }
            throw SSHConnectError.invalidPrivateKey
        }
        guard let password, !password.isEmpty else {
            throw SSHConnectError.missingCredentials
        }
        return .passwordBased(username: user, password: password)
    }
}

public enum SSHConnectError: LocalizedError {
    case missingCredentials
    case invalidPrivateKey
    case disconnected
    case unreachable
    case timeout
    case authFailed
    case hostKeyMismatch
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "SSH requires a password or a private key."
        case .invalidPrivateKey:
            return "Unable to parse the SSH private key."
        case .disconnected:
            return "SSH session disconnected."
        case .unreachable:
            return "Host is unreachable on the given port."
        case .timeout:
            return "SSH connection timed out."
        case .authFailed:
            return "Authentication failed. Check username, password or key."
        case .hostKeyMismatch:
            return "Host key changed. The server identity does not match the key saved from the last connection."
        case .cancelled:
            return "Connection cancelled."
        }
    }
}

/// First-seen host keys are remembered; a later mismatch fails the handshake.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let encoded = String(openSSHPublicKey: hostKey)
        do {
            try HostKeyStore.shared.verifyOrRemember(host: host, port: port, openSSHKey: encoded)
            validationCompletePromise.succeed(())
        } catch {
            validationCompletePromise.fail(error)
        }
    }
}

private final class ProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Bool, Never>
    private let connection: NWConnection

    init(continuation: CheckedContinuation<Bool, Never>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        connection.cancel()
        continuation.resume(returning: value)
    }
}

public enum SSHReachability {
    public static func probe(host: String, port: Int, timeout: TimeInterval = 4) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let box = ProbeBox(continuation: continuation, connection: connection)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.finish(true)
                case .failed, .cancelled:
                    box.finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                box.finish(false)
            }
        }
    }

    public static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw SSHConnectError.timeout
            }
            guard let result = try await group.next() else {
                throw SSHConnectError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
