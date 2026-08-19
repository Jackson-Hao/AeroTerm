import Foundation
import SwiftUI
import AppKit
import Combine
import Network
@preconcurrency import Citadel

public enum PendingDestructiveAction: Equatable, Sendable {
    case closeSession(UUID)
    case deleteConnection(UUID)
}

public enum SidebarTab: Int, CaseIterable, Identifiable, Sendable {
    case saved = 0
    case active = 1

    public var id: Int { rawValue }
}

@MainActor
public final class SessionManager: ObservableObject {
    public static let shared = SessionManager()

    @Published public var columnVisibility: NavigationSplitViewVisibility = .all
    @Published public var sidebarTab: SidebarTab = .saved
    @Published public var isFullScreen: Bool = false
    @Published public var isShowingNewConnectionWizard: Bool = false
    
    // 默认冷启动时展示独立的 Xcode 欢迎窗口
    @Published public var isShowingStartupSplash: Bool = true
    @Published public var isVaultReady: Bool = false
    
    @Published public var savedConnections: [ConnectionConfig] = []
    @Published public var accounts: [AuthAccount] = []
    @Published public var sessions: [SessionItem] = []
    @Published public var activeSessionID: UUID? = nil
    @Published public var recentConnections: [RecentConnection] = []
    @Published public var alertMessage: String? = nil
    @Published public var isShowingAccountManager: Bool = false
    @Published public var pendingDestructiveAction: PendingDestructiveAction? = nil

    // Dedicated tool engines per tab session
    public var tcpClientEngines: [UUID: TCPClientEngine] = [:]
    public var tcpServerEngines: [UUID: TCPServerEngine] = [:]
    public var udpEngines: [UUID: UDPEngine] = [:]
    public var serialEngines: [UUID: SerialEngine] = [:]
    public var serialTerminals: [UUID: SerialTerminalSession] = [:]
    public var telnetSessions: [UUID: TelnetTerminalSession] = [:]
    public var sshSessions: [UUID: SSHTerminalSession] = [:]
    public var sftpSessions: [UUID: SFTPBrowserSession] = [:]
    public var agentCLISessions: [UUID: AgentCLISession] = [:]
    public var httpClients: [UUID: HTTPClientController] = [:]
    public var httpServers: [UUID: HTTPServerEngine] = [:]
    public var vncSessions: [UUID: VNCDesktopSession] = [:]
    public var rdpSessions: [UUID: RDPDesktopSession] = [:]
    private var remoteActivity: NSObjectProtocol?
    private var connectTask: Task<Void, Never>?

    @Published public var connectionHUD: ConnectionHUDState? = nil
    @Published public var surfaces: [WorkspaceSurface] = [WorkspaceSurface.makePrimary()]
    @Published public var focusedSurfaceID: UUID = WorkspaceSurface.primaryID
    @Published public var windowCommands: [WorkspaceWindowCommand] = []
    var pendingDropPlacement: PendingDropPlacement? = nil

    private let legacySavedKey = "AeroTerm.SavedConnections.v5"
    private let legacyRecentKey = "AeroTerm.RecentConnections.v5"

    public init() {
        self.isShowingStartupSplash = true
        loadData()
    }

    public var activeSession: SessionItem? {
        guard let activeSessionID = activeSessionID else { return nil }
        return sessions.first(where: { $0.id == activeSessionID })
    }

    public func showWizard(defaultType: SessionType? = nil) {
        isShowingNewConnectionWizard = true
    }

    public var isSidebarCollapsed: Bool {
        columnVisibility == .detailOnly
    }

    public func toggleSidebar() {
        columnVisibility = isSidebarCollapsed ? .all : .detailOnly
    }

    public func closeWizard(enterWorkbench shouldEnter: Bool) {
        if shouldEnter {
            enterWorkbench()
        } else {
            isShowingNewConnectionWizard = false
        }
    }

    /// 关掉欢迎页 / 向导，进入主工作区。两个开关必须一起改，避免先回到 Splash。
    public func enterWorkbench() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // 先关 Splash，避免 Wizard=false 时还停在欢迎页。
            isShowingStartupSplash = false
            isShowingNewConnectionWizard = false
            columnVisibility = .all
            if !sessions.isEmpty {
                sidebarTab = .active
                if activeSessionID == nil {
                    activeSessionID = sessions.first?.id
                }
            }
        }
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow ?? NSApp.windows.first {
                WindowChrome.sync(window)
            }
        }
    }

    @discardableResult
    public func openFromConfig(_ config: ConnectionConfig) -> Bool {
        if config.type == .agentCLI {
            openAgentCLI(
                title: config.name,
                command: config.host,
                arguments: config.customArgs,
                workingDirectory: config.workingDirectory,
                environment: config.envVars
            )
            return true
        }

        let result = openSession(
            type: config.type,
            host: config.host,
            port: config.port,
            title: config.name,
            username: resolvedUsername(for: config),
            connectionID: config.id,
            accountID: config.accountID,
            localPort: config.localPort,
            udpMode: config.udpMode,
            label: config.label,
            serial: config.serial,
            desktop: config.desktop
        )
        if result {
            sidebarTab = .active
        }
        return result
    }

    @discardableResult
    public func openSession(
        type: SessionType,
        host: String = "127.0.0.1",
        port: Int = 22,
        title: String? = nil,
        username: String? = nil,
        connectionID: UUID? = nil,
        accountID: UUID? = nil,
        forceNew: Bool = false,
        localPort: Int = 0,
        udpMode: UDPMode = .unicast,
        label: String = "",
        serial: SerialSettings = .default,
        desktop: DesktopDisplaySettings = .default
    ) -> Bool {
        if !forceNew,
           let existing = existingSession(
            type: type,
            host: host,
            port: port,
            connectionID: connectionID,
            accountID: accountID
           ) {
            selectSession(existing.id)
            if type.usesAccountAuth, !existing.isConnected {
                reconnect(existing)
            }
            return true
        }

        if type.usesAccountAuth {
            let matched = connectionID.flatMap { id in
                savedConnections.first(where: { $0.id == id })
            }
            let aid = accountID ?? matched?.accountID
            let user = username
                ?? (aid.flatMap { account(id: $0)?.username })
                ?? matched?.username
                ?? ""
            let config = ConnectionConfig(
                id: connectionID ?? matched?.id ?? UUID(),
                name: title ?? "\(type.rawValue) - \(user)@\(host):\(port)",
                type: type,
                host: host,
                port: port,
                username: user,
                accountID: aid,
                desktop: matched?.desktop ?? desktop
            )
            return beginRemoteConnect(config, saveOnSuccess: false)
        }

        if type == .serial {
            return openSerialSession(
                host: host,
                port: port,
                title: title,
                username: username,
                connectionID: connectionID,
                serial: serial
            )
        }

        let displayTitle = title ?? (type == .httpClient ? type.rawValue : "\(type.rawValue) - \(host):\(port)")
        let subtitle: String
        if type == .httpClient {
            subtitle = label.isEmpty ? type.rawValue : label
        } else if let username, !username.isEmpty {
            subtitle = "\(username)@\(host):\(port)"
        } else {
            subtitle = "\(host):\(port)"
        }
        let session = SessionItem(
            title: displayTitle,
            subtitle: subtitle,
            type: type,
            isConnected: type != .tcpClient && type != .tcpServer && type != .udpTool && type != .httpServer,
            host: type == .httpClient ? "" : host,
            port: type == .httpClient ? 0 : port,
            localPort: localPort,
            udpMode: udpMode,
            connectionID: connectionID,
            label: label
        )

        switch type {
        case .tcpClient:
            tcpClientEngines[session.id] = TCPClientEngine()
        case .tcpServer:
            tcpServerEngines[session.id] = TCPServerEngine()
        case .udpTool:
            udpEngines[session.id] = UDPEngine()
        case .httpClient:
            httpClients[session.id] = HTTPClientController()
        case .httpServer:
            httpServers[session.id] = HTTPServerEngine()
        case .agentCLI:
            break
        case .ssh, .sftp, .telnet, .vnc, .rdp, .serial:
            break
        }

        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active
        revealSession(session.id)

        addRecent(RecentConnection(title: displayTitle, type: type, host: host, port: port, username: username))
        return true
    }

    @discardableResult
    private func openSerialSession(
        host: String,
        port: Int,
        title: String?,
        username: String?,
        connectionID: UUID?,
        serial: SerialSettings
    ) -> Bool {
        let available = SerialEngine.getAvailablePorts()
        let targetPath: String
        if host.hasPrefix("/dev") || !host.isEmpty {
            targetPath = host
        } else if let first = available.first {
            targetPath = first.path
        } else {
            targetPath = ""
        }
        let baud = port > 0 ? port : 115200
        let shortName = targetPath.replacingOccurrences(of: "/dev/cu.", with: "")
        let displayTitle = title ?? (shortName.isEmpty ? "Serial" : "Serial - \(shortName)")
        let subtitle = "\(serial.mode.title) · \(baud) \(serial.detailLabel)"

        let engine = SerialEngine()
        engine.selectedPortPath = targetPath
        engine.baudRate = baud
        engine.settings = serial

        var opened = false
        if serial.mode == .shell, !targetPath.isEmpty {
            opened = engine.openPort(path: targetPath, baud: baud, settings: serial)
            if !opened {
                alertMessage = "\(LocalizationManager.shared.text("serial_open_failed")) \(targetPath)"
            }
        }

        let session = SessionItem(
            title: displayTitle,
            subtitle: subtitle,
            type: .serial,
            isConnected: opened,
            host: targetPath,
            port: baud,
            targetDevice: targetPath,
            connectionID: connectionID,
            serial: serial
        )
        serialEngines[session.id] = engine
        if serial.mode == .shell {
            let runtime = SerialTerminalSession(engine: engine, sessionID: session.id, settings: serial)
            serialTerminals[session.id] = runtime
            runtime.start()
        }
        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active
        revealSession(session.id)
        addRecent(RecentConnection(title: displayTitle, type: .serial, host: targetPath, port: baud, username: username))
        return true
    }

    public func saveConnection(_ config: ConnectionConfig, connectImmediately: Bool = true) {
        if let index = savedConnections.firstIndex(where: { $0.id == config.id }) {
            savedConnections[index] = config
        } else {
            savedConnections.insert(config, at: 0)
        }
        persistAll()

        if connectImmediately {
            if config.type.usesAccountAuth {
                _ = beginRemoteConnect(config, saveOnSuccess: false)
            } else {
                openFromConfig(config)
            }
        }
    }

    public func account(id: UUID?) -> AuthAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    public func accounts(for type: SessionType) -> [AuthAccount] {
        accounts.filter { $0.kind.supports(type) }
    }

    public func resolvedUsername(for config: ConnectionConfig) -> String {
        account(id: config.accountID)?.username ?? config.username
    }

    public func upsertAccount(_ account: AuthAccount) {
        var item = account
        item.updatedAt = Date()
        if let index = accounts.firstIndex(where: { $0.id == item.id }) {
            accounts[index] = item
        } else {
            accounts.insert(item, at: 0)
        }
        persistAll()
    }

    public func deleteAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        SecretStore.shared.deleteAll(accountID: id)
        for index in savedConnections.indices where savedConnections[index].accountID == id {
            savedConnections[index].accountID = nil
        }
        for index in recentConnections.indices where recentConnections[index].accountID == id {
            recentConnections[index].accountID = nil
        }
        persistAll()
    }

    public func dismissConnectionHUD() {
        connectionHUD = nil
    }

    public func cancelRemoteConnect() {
        if let hud = connectionHUD {
            hud.isCancelled = true
            hud.isFinished = true
        }
        connectTask?.cancel()
        connectTask = nil
        connectionHUD = nil
        cancelPendingDropPlacement()
    }

    /// SSH / SFTP 共用账号密钥：先验证，成功后再按需保存连接。
    @discardableResult
    public func beginSSHConnect(_ config: ConnectionConfig, saveOnSuccess: Bool = false) -> Bool {
        beginRemoteConnect(config, saveOnSuccess: saveOnSuccess)
    }

    @discardableResult
    public func beginRemoteConnect(
        _ config: ConnectionConfig,
        saveOnSuccess: Bool = false,
        replacingSessionID: UUID? = nil
    ) -> Bool {
        if let hud = connectionHUD, !hud.isFinished {
            return false
        }
        guard config.type.usesAccountAuth else { return false }
        guard let accountID = config.accountID, let account = account(id: accountID) else {
            alertMessage = LocalizationManager.shared.text("account_required")
            return false
        }
        if account.kind.requiresUsername, account.username.isEmpty {
            alertMessage = LocalizationManager.shared.text("ssh_username_required")
            return false
        }
        if account.kind.requiresSecret {
            let hasNeededSecret = account.authMethod == .publicKey
                ? SecretStore.shared.get(.privateKey, accountID: accountID) != nil
                : SecretStore.shared.get(.password, accountID: accountID) != nil
            if !hasNeededSecret {
                alertMessage = LocalizationManager.shared.text("ssh_credentials_required")
                return false
            }
        }

        if replacingSessionID == nil,
           let existing = existingSession(
            type: config.type,
            host: config.host,
            port: config.port,
            connectionID: config.id,
            accountID: accountID
           ) {
            selectSession(existing.id)
            if existing.isConnected {
                return true
            }
        }

        var resolved = config
        resolved.username = account.username
        resolved.authMethod = account.authMethod

        let userLabel = account.username.isEmpty ? config.host : "\(account.username)@\(config.host)"
        let target = "\(userLabel):\(config.port)"
        let title: String
        switch config.type {
        case .sftp: title = "Connecting SFTP"
        case .telnet: title = "Connecting Telnet"
        case .vnc: title = "Connecting VNC"
        case .rdp: title = "Connecting RDP"
        default: title = "Connecting"
        }
        let hud = ConnectionHUDState(title: title, subtitle: target)
        connectionHUD = hud
        let replaceID = replacingSessionID
            ?? existingSession(
                type: resolved.type,
                host: resolved.host,
                port: resolved.port,
                connectionID: resolved.id,
                accountID: resolved.accountID
            )?.id
            ?? disconnectedSessionID(matching: resolved)
        switch config.type {
        case .telnet:
            connectTask = Task { await runTelnetConnectPipeline(config: resolved, account: account, hud: hud, saveOnSuccess: saveOnSuccess, replacingSessionID: replaceID) }
        case .vnc:
            connectTask = Task { await runVNCConnectPipeline(config: resolved, account: account, hud: hud, saveOnSuccess: saveOnSuccess, replacingSessionID: replaceID) }
        case .rdp:
            connectTask = Task { await runRDPConnectPipeline(config: resolved, account: account, hud: hud, saveOnSuccess: saveOnSuccess, replacingSessionID: replaceID) }
        default:
            connectTask = Task { await runRemoteConnectPipeline(config: resolved, account: account, hud: hud, saveOnSuccess: saveOnSuccess, replacingSessionID: replaceID) }
        }
        return true
    }

    public func reconnect(_ session: SessionItem) {
        guard session.type.usesAccountAuth, !session.isConnected else { return }
        let config = ConnectionConfig(
            id: session.connectionID ?? UUID(),
            name: session.title,
            type: session.type,
            host: session.host,
            port: session.port,
            username: session.customCommand ?? "",
            accountID: session.accountID,
            desktop: session.desktop
        )
        _ = beginRemoteConnect(config, saveOnSuccess: false, replacingSessionID: session.id)
    }

    private func existingSession(
        type: SessionType,
        host: String,
        port: Int,
        connectionID: UUID?,
        accountID: UUID?
    ) -> SessionItem? {
        if let connectionID,
           let hit = sessions.first(where: { $0.connectionID == connectionID && $0.type == type }) {
            return hit
        }
        if type == .httpClient {
            return nil
        }
        if type == .serial {
            return sessions.first(where: { $0.type == .serial && $0.host == host && !host.isEmpty })
        }
        return sessions.first(where: {
            $0.type == type
                && $0.host == host
                && $0.port == port
                && $0.accountID == accountID
        })
    }

    private func disconnectedSessionID(matching config: ConnectionConfig) -> UUID? {
        sessions.first(where: { session in
            !session.isConnected
                && session.type == config.type
                && session.host == config.host
                && session.port == config.port
                && session.accountID == config.accountID
        })?.id
    }

    private func runTelnetConnectPipeline(
        config: ConnectionConfig,
        account: AuthAccount,
        hud: ConnectionHUDState,
        saveOnSuccess: Bool,
        replacingSessionID: UUID?
    ) async {
        if connectWasCancelled(hud) { return }
        hud.log("Preparing Telnet session…")
        hud.log("Probing \(config.host):\(config.port)")
        let reachable = await SSHReachability.probe(host: config.host, port: config.port, timeout: 4)
        if connectWasCancelled(hud) { return }
        guard reachable else {
            hud.log("Host unreachable", kind: .error)
            hud.isFinished = true
            cancelPendingDropPlacement()
            return
        }
        hud.log("Port is open", kind: .success)

        let password = SecretStore.shared.get(.password, accountID: account.id)
        var lastError: Error = TelnetConnectError.timeout
        for attempt in 1...3 {
            if connectWasCancelled(hud) { return }
            hud.log("Connecting (attempt \(attempt)/3)…")
            do {
                let connection = try await SSHReachability.withTimeout(seconds: 8) {
                    try await TelnetConnector.connect(host: config.host, port: config.port)
                }
                if connectWasCancelled(hud) {
                    connection.cancel()
                    return
                }
                hud.log("Connected", kind: .success)
                hud.log("Opening terminal session…")
                if saveOnSuccess {
                    saveConnection(config, connectImmediately: false)
                    hud.log("Connection saved", kind: .success)
                }
                attachTelnetSession(config: config, connection: connection, password: password, replacingSessionID: replacingSessionID)
                hud.log("Ready", kind: .success)
                hud.didSucceed = true
                hud.isFinished = true
                enterWorkbench()
                try? await Task.sleep(for: .milliseconds(450))
                if connectionHUD === hud {
                    connectionHUD = nil
                }
                return
            } catch {
                lastError = error
                if connectWasCancelled(hud) { return }
                hud.log(error.localizedDescription, kind: .error)
                if attempt < 3 {
                    hud.log("Retrying…", kind: .warning)
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }
        hud.log("Gave up after 3 attempts. \(lastError.localizedDescription)", kind: .error)
        hud.isFinished = true
        cancelPendingDropPlacement()
    }

    private func runRemoteConnectPipeline(
        config: ConnectionConfig,
        account: AuthAccount,
        hud: ConnectionHUDState,
        saveOnSuccess: Bool,
        replacingSessionID: UUID?
    ) async {
        if connectWasCancelled(hud) { return }
        hud.log(config.type == .sftp ? "Preparing SFTP session…" : "Preparing SSH session…")
        hud.log("Probing \(config.host):\(config.port)")
        let reachable = await SSHReachability.probe(host: config.host, port: config.port, timeout: 4)
        if connectWasCancelled(hud) { return }
        guard reachable else {
            hud.log("Host unreachable", kind: .error)
            hud.isFinished = true
            cancelPendingDropPlacement()
            return
        }
        hud.log("Port is open", kind: .success)

        let password = SecretStore.shared.get(.password, accountID: account.id)
        let privateKey = SecretStore.shared.get(.privateKey, accountID: account.id)
        let passphrase = SecretStore.shared.get(.keyPassphrase, accountID: account.id)
        let user = account.username
        let host = config.host
        let port = config.port
        let authMethod = account.authMethod

        let auth: SSHAuthenticationMethod
        do {
            auth = try SSHAuthBuilder.makeMethod(
                username: user,
                authMethod: authMethod,
                password: password,
                privateKeyPEM: privateKey,
                keyPassphrase: passphrase
            )
        } catch {
            hud.log(error.localizedDescription, kind: .error)
            hud.isFinished = true
            cancelPendingDropPlacement()
            return
        }

        var lastError: Error = SSHConnectError.authFailed
        for attempt in 1...3 {
            if connectWasCancelled(hud) { return }
            hud.log("Authenticating (attempt \(attempt)/3)…")
            do {
                let client = try await SSHReachability.withTimeout(seconds: 8) {
                    var settings = SSHClientSettings(
                        host: host,
                        port: port,
                        authenticationMethod: { auth },
                        hostKeyValidator: .custom(TOFUHostKeyValidator(host: host, port: port))
                    )
                    settings.connectTimeout = .seconds(8)
                    return try await SSHClient.connect(to: settings)
                }
                if connectWasCancelled(hud) {
                    try? await client.close()
                    return
                }
                hud.log("Authenticated", kind: .success)

                if config.type == .sftp {
                    do {
                        hud.log("Opening SFTP subsystem…")
                        let sftp = try await SSHReachability.withTimeout(seconds: 15) {
                            try await client.openSFTP()
                        }
                        if connectWasCancelled(hud) {
                            try? await sftp.close()
                            try? await client.close()
                            return
                        }
                        hud.log("SFTP ready", kind: .success)
                        if saveOnSuccess {
                            saveConnection(config, connectImmediately: false)
                            hud.log("Connection saved", kind: .success)
                        }
                        attachSFTPSession(config: config, ssh: client, sftp: sftp, replacingSessionID: replacingSessionID)
                    } catch {
                        try? await client.close()
                        throw error
                    }
                } else {
                    hud.log("Opening terminal session…")
                    if saveOnSuccess {
                        saveConnection(config, connectImmediately: false)
                        hud.log("Connection saved", kind: .success)
                    }
                    attachSSHSession(config: config, client: client, replacingSessionID: replacingSessionID)
                }

                hud.log("Connected", kind: .success)
                hud.didSucceed = true
                hud.isFinished = true
                enterWorkbench()
                try? await Task.sleep(for: .milliseconds(450))
                if connectionHUD === hud {
                    connectionHUD = nil
                }
                return
            } catch {
                lastError = error
                if connectWasCancelled(hud) { return }
                hud.log(error.localizedDescription, kind: .error)
                if error is SSHConnectError, case .hostKeyMismatch = (error as? SSHConnectError) {
                    break
                }
                if attempt < 3 {
                    hud.log("Retrying…", kind: .warning)
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }
        hud.log("Gave up after 3 attempts. \(lastError.localizedDescription)", kind: .error)
        hud.isFinished = true
        cancelPendingDropPlacement()
    }

    private func connectWasCancelled(_ hud: ConnectionHUDState) -> Bool {
        hud.isCancelled || Task.isCancelled
    }

    private func attachSSHSession(config: ConnectionConfig, client: SSHClient, replacingSessionID: UUID?) {
        let sessionID = reuseOrCreateRemoteSession(config: config, type: .ssh, replacingSessionID: replacingSessionID)
        if let previous = sshSessions.removeValue(forKey: sessionID) {
            Task { await previous.shutdown() }
        }
        let runtime = SSHTerminalSession(client: client, sessionID: sessionID)
        sshSessions[sessionID] = runtime
        runtime.start()
        refreshRemoteActivity()
    }

    private func attachSFTPSession(config: ConnectionConfig, ssh: SSHClient, sftp: SFTPClient, replacingSessionID: UUID?) {
        let sessionID = reuseOrCreateRemoteSession(config: config, type: .sftp, replacingSessionID: replacingSessionID)
        if let previous = sftpSessions.removeValue(forKey: sessionID) {
            Task { await previous.shutdown() }
        }
        let browser = SFTPBrowserSession(ssh: ssh, sftp: sftp, sessionID: sessionID)
        sftpSessions[sessionID] = browser
        browser.start()
        refreshRemoteActivity()
    }

    private func attachTelnetSession(
        config: ConnectionConfig,
        connection: NWConnection,
        password: String?,
        replacingSessionID: UUID?
    ) {
        let sessionID = reuseOrCreateRemoteSession(config: config, type: .telnet, replacingSessionID: replacingSessionID)
        if let previous = telnetSessions.removeValue(forKey: sessionID) {
            Task { await previous.shutdown() }
        }
        let runtime = TelnetTerminalSession(
            connection: connection,
            sessionID: sessionID,
            username: config.username,
            password: password
        )
        telnetSessions[sessionID] = runtime
        runtime.start()
        refreshRemoteActivity()
    }

    private func attachVNCSession(config: ConnectionConfig, runtime: VNCDesktopSession, replacingSessionID: UUID?) {
        let sessionID = reuseOrCreateRemoteSession(config: config, type: .vnc, replacingSessionID: replacingSessionID)
        if let previous = vncSessions.removeValue(forKey: sessionID), previous !== runtime {
            previous.shutdown()
        }
        runtime.rebind(sessionID: sessionID)
        vncSessions[sessionID] = runtime
        refreshRemoteActivity()
    }

    private func attachRDPSession(config: ConnectionConfig, runtime: RDPDesktopSession, replacingSessionID: UUID?) {
        let sessionID = reuseOrCreateRemoteSession(config: config, type: .rdp, replacingSessionID: replacingSessionID)
        if let previous = rdpSessions.removeValue(forKey: sessionID), previous !== runtime {
            previous.shutdown()
        }
        runtime.rebind(sessionID: sessionID)
        rdpSessions[sessionID] = runtime
        refreshRemoteActivity()
    }

    private func runVNCConnectPipeline(
        config: ConnectionConfig,
        account: AuthAccount,
        hud: ConnectionHUDState,
        saveOnSuccess: Bool,
        replacingSessionID: UUID?
    ) async {
        if connectWasCancelled(hud) { return }
        hud.log("Preparing VNC session…")
        hud.log("Probing \(config.host):\(config.port)")
        let reachable = await SSHReachability.probe(host: config.host, port: config.port, timeout: 4)
        if connectWasCancelled(hud) { return }
        guard reachable else {
            hud.log("Host unreachable", kind: .error)
            hud.isFinished = true
            cancelPendingDropPlacement()
            return
        }
        hud.log("Port is open", kind: .success)

        let password = SecretStore.shared.get(.password, accountID: account.id) ?? ""
        var lastError: Error = VNCConnectError.timeout
        for attempt in 1...3 {
            if connectWasCancelled(hud) { return }
            hud.log("Connecting (attempt \(attempt)/3)…")
            let runtime = VNCDesktopSession(
                sessionID: replacingSessionID ?? UUID(),
                host: config.host,
                port: config.port,
                username: account.username,
                password: password,
                display: config.desktop
            )
            do {
                try await withTaskCancellationHandler {
                    try await runtime.connect()
                } onCancel: {
                    Task { @MainActor in
                        runtime.shutdown()
                    }
                }
                if connectWasCancelled(hud) {
                    runtime.shutdown()
                    return
                }
                hud.log("Connected", kind: .success)
                if saveOnSuccess {
                    saveConnection(config, connectImmediately: false)
                    hud.log("Connection saved", kind: .success)
                }
                attachVNCSession(config: config, runtime: runtime, replacingSessionID: replacingSessionID)
                hud.log("Ready", kind: .success)
                hud.didSucceed = true
                hud.isFinished = true
                enterWorkbench()
                try? await Task.sleep(for: .milliseconds(450))
                if connectionHUD === hud {
                    connectionHUD = nil
                }
                return
            } catch {
                lastError = error
                runtime.shutdown()
                if connectWasCancelled(hud) { return }
                hud.log(error.localizedDescription, kind: .error)
                if attempt < 3 {
                    hud.log("Retrying…", kind: .warning)
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }
        hud.log("Gave up after 3 attempts. \(lastError.localizedDescription)", kind: .error)
        hud.isFinished = true
        cancelPendingDropPlacement()
    }

    private func runRDPConnectPipeline(
        config: ConnectionConfig,
        account: AuthAccount,
        hud: ConnectionHUDState,
        saveOnSuccess: Bool,
        replacingSessionID: UUID?
    ) async {
        if connectWasCancelled(hud) { return }
        hud.log("Preparing RDP session…")
        hud.log("Probing \(config.host):\(config.port)")
        let reachable = await SSHReachability.probe(host: config.host, port: config.port, timeout: 4)
        if connectWasCancelled(hud) { return }
        guard reachable else {
            hud.log("Host unreachable", kind: .error)
            hud.isFinished = true
            cancelPendingDropPlacement()
            return
        }
        hud.log("Port is open", kind: .success)

        let password = SecretStore.shared.get(.password, accountID: account.id) ?? ""
        var lastError: Error = RDPConnectError.cancelled
        for attempt in 1...3 {
            if connectWasCancelled(hud) { return }
            hud.log("Connecting (attempt \(attempt)/3)…")
            let runtime = RDPDesktopSession(sessionID: replacingSessionID ?? UUID())
            do {
                try await withTaskCancellationHandler {
                    try await runtime.start(
                        host: config.host,
                        port: config.port,
                        username: account.username,
                        password: password,
                        desktopSize: RemoteDesktopGeometry.fallbackPointSize(),
                        display: config.desktop
                    )
                } onCancel: {
                    Task { @MainActor in
                        runtime.shutdown()
                    }
                }
                if connectWasCancelled(hud) {
                    runtime.shutdown()
                    return
                }
                hud.log("Connected", kind: .success)
                if saveOnSuccess {
                    saveConnection(config, connectImmediately: false)
                    hud.log("Connection saved", kind: .success)
                }
                attachRDPSession(config: config, runtime: runtime, replacingSessionID: replacingSessionID)
                hud.log("Ready", kind: .success)
                hud.didSucceed = true
                hud.isFinished = true
                enterWorkbench()
                try? await Task.sleep(for: .milliseconds(450))
                if connectionHUD === hud {
                    connectionHUD = nil
                }
                return
            } catch {
                lastError = error
                runtime.shutdown()
                if connectWasCancelled(hud) { return }
                hud.log(error.localizedDescription, kind: .error)
                if attempt < 3 {
                    hud.log("Retrying…", kind: .warning)
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }
        hud.log("Gave up after 3 attempts. \(lastError.localizedDescription)", kind: .error)
        hud.isFinished = true
        cancelPendingDropPlacement()
    }

    @discardableResult
    private func reuseOrCreateRemoteSession(
        config: ConnectionConfig,
        type: SessionType,
        replacingSessionID: UUID?
    ) -> UUID {
        let existingID = replacingSessionID.flatMap { id in
            sessions.contains(where: { $0.id == id }) ? id : nil
        }
        if let existingID, let index = sessions.firstIndex(where: { $0.id == existingID }) {
            sessions[index].isConnected = true
            sessions[index].isSuspended = false
            sessions[index].subtitle = "\(config.username)@\(config.host):\(config.port)"
            sessions[index].host = config.host
            sessions[index].port = config.port
            sessions[index].customCommand = config.username
            sessions[index].connectionID = config.id
            sessions[index].accountID = config.accountID
            sessions[index].desktop = config.desktop
            activeSessionID = existingID
            sidebarTab = .active
            revealSession(existingID)
            addRecent(RecentConnection(
                title: config.name,
                type: type,
                host: config.host,
                port: config.port,
                username: config.username,
                accountID: config.accountID
            ))
            return existingID
        }

        let session = SessionItem(
            title: uniqueSessionTitle(config.name),
            subtitle: "\(config.username)@\(config.host):\(config.port)",
            type: type,
            isConnected: true,
            host: config.host,
            port: config.port,
            customCommand: config.username,
            connectionID: config.id,
            accountID: config.accountID,
            desktop: config.desktop
        )
        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active
        revealSession(session.id)
        addRecent(RecentConnection(
            title: config.name,
            type: type,
            host: config.host,
            port: config.port,
            username: config.username,
            accountID: config.accountID
        ))
        return session.id
    }

    private func uniqueSessionTitle(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Session" : trimmed
        if !sessions.contains(where: { $0.title == name }) {
            return name
        }
        var index = 2
        while sessions.contains(where: { $0.title == "\(name) (\(index))" }) {
            index += 1
        }
        return "\(name) (\(index))"
    }

    public func duplicateSession(_ session: SessionItem) {
        let title = Self.baseSessionTitle(session.title)
        if session.type == .agentCLI {
            openAgentCLI(
                title: title,
                command: session.host,
                arguments: session.customCommand,
                workingDirectory: session.workingDirectory ?? session.targetDevice,
                environment: session.environmentVariables
            )
            return
        }

        let accountID = session.accountID
            ?? savedConnections.first(where: { $0.id == session.connectionID })?.accountID
            ?? accounts.first(where: { $0.username == session.customCommand })?.id
        _ = openSession(
            type: session.type,
            host: session.host,
            port: session.port,
            title: title,
            username: session.customCommand,
            connectionID: session.connectionID,
            accountID: accountID,
            forceNew: true,
            localPort: session.localPort,
            udpMode: session.udpMode,
            label: session.label,
            serial: session.serial,
            desktop: session.desktop
        )
    }

    public func setSessionSuspended(id: UUID, _ suspended: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].isSuspended = suspended
        if !suspended {
            activeSessionID = id
            sidebarTab = .active
        }
    }

    public func toggleSessionSuspended(id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        setSessionSuspended(id: id, !session.isSuspended)
    }

    private static func baseSessionTitle(_ title: String) -> String {
        if let range = title.range(of: #" \(\d+\)$"#, options: .regularExpression) {
            return String(title[..<range.lowerBound])
        }
        return title
    }

    public func updateDesktopDisplay(for sessionID: UUID, desktop: DesktopDisplaySettings) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].desktop = desktop
            if let connectionID = sessions[index].connectionID,
               let savedIndex = savedConnections.firstIndex(where: { $0.id == connectionID }) {
                savedConnections[savedIndex].desktop = desktop
                persistAll()
            }
        }
        vncSessions[sessionID]?.applyDisplaySettings(desktop)
        rdpSessions[sessionID]?.applyDisplaySettings(desktop)
    }

    public func markSessionDisconnected(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].isConnected {
            sessions[index].isConnected = false
        }
        refreshRemoteActivity()
    }

    public func markSessionConnected(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if !sessions[index].isConnected {
            sessions[index].isConnected = true
        }
    }

    public func updateSessionUDPMode(id: UUID, mode: UDPMode) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].udpMode = mode
    }

    public func updateSerialEndpoint(id: UUID, host: String, port: Int) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].host = host
        sessions[index].port = port
        sessions[index].targetDevice = host
        let serial = sessions[index].serial
        sessions[index].subtitle = "\(serial.mode.title) · \(port) \(serial.detailLabel)"
    }

    public func updateSessionEndpoint(id: UUID, host: String, port: Int, localPort: Int? = nil) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].host = host
        sessions[index].port = port
        if let localPort {
            sessions[index].localPort = localPort
        }
        let user = sessions[index].customCommand
        if let user, !user.isEmpty {
            sessions[index].subtitle = "\(user)@\(host):\(port)"
        } else {
            sessions[index].subtitle = "\(host):\(port)"
        }
    }

    @discardableResult
    public func importConnections(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            if let decoded = try? JSONDecoder().decode([ConnectionConfig].self, from: data) {
                for item in decoded {
                    saveConnection(item, connectImmediately: false)
                }
                self.alertMessage = "\(LocalizationManager.shared.text("import_success")) (\(decoded.count))"
                return true
            } else {
                self.alertMessage = LocalizationManager.shared.text("import_failed")
                return false
            }
        } catch {
            self.alertMessage = "\(LocalizationManager.shared.text("import_failed")): \(error.localizedDescription)"
            return false
        }
    }

    public func deleteSavedConnection(id: UUID) {
        savedConnections.removeAll { $0.id == id }
        persistAll()
    }

    public func requestCloseSession(id: UUID) {
        pendingDestructiveAction = .closeSession(id)
    }

    public func requestDeleteConnection(id: UUID) {
        pendingDestructiveAction = .deleteConnection(id)
    }

    public func confirmPendingDestructiveAction() {
        switch pendingDestructiveAction {
        case .closeSession(let id):
            closeSession(id: id)
        case .deleteConnection(let id):
            deleteSavedConnection(id: id)
        case nil:
            break
        }
        pendingDestructiveAction = nil
    }

    public func cancelPendingDestructiveAction() {
        pendingDestructiveAction = nil
    }

    public func pendingDestructiveTitle(using loc: LocalizationManager) -> String {
        switch pendingDestructiveAction {
        case .closeSession:
            return loc.text("session_close_confirm_title")
        case .deleteConnection:
            return loc.text("delete_config_confirm_title")
        case nil:
            return loc.text("alert_title")
        }
    }

    public func pendingDestructiveMessage(using loc: LocalizationManager) -> String {
        switch pendingDestructiveAction {
        case .closeSession(let id):
            let name = sessions.first(where: { $0.id == id })?.title ?? ""
            return String(format: loc.text("session_close_confirm_msg"), name)
        case .deleteConnection(let id):
            let name = savedConnections.first(where: { $0.id == id })?.name ?? ""
            return String(format: loc.text("delete_config_confirm_msg"), name)
        case nil:
            return ""
        }
    }

    public func pendingDestructiveConfirmLabel(using loc: LocalizationManager) -> String {
        switch pendingDestructiveAction {
        case .closeSession:
            return loc.text("session_close")
        case .deleteConnection:
            return loc.text("delete_config_confirm_btn")
        case nil:
            return loc.text("ok")
        }
    }

    public func closeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        pruneSessionFromLayouts(id)

        let targetActiveID: UUID?
        if activeSessionID == id {
            if sessions.count > 1 {
                // 如果关闭的是最后一个，选前一个；否则选后一个
                let nextIdx = (index == sessions.count - 1) ? index - 1 : index + 1
                targetActiveID = sessions[nextIdx].id
            } else {
                targetActiveID = nil
            }
        } else {
            targetActiveID = activeSessionID
        }

        sessions.remove(at: index)
        activeSessionID = targetActiveID

        let serial = serialEngines.removeValue(forKey: id)
        let serialTerm = serialTerminals.removeValue(forKey: id)
        let tcpClient = tcpClientEngines.removeValue(forKey: id)
        let tcpServer = tcpServerEngines.removeValue(forKey: id)
        let udp = udpEngines.removeValue(forKey: id)
        let ssh = sshSessions.removeValue(forKey: id)
        let sftp = sftpSessions.removeValue(forKey: id)
        let telnet = telnetSessions.removeValue(forKey: id)
        let agent = agentCLISessions.removeValue(forKey: id)
        let httpClient = httpClients.removeValue(forKey: id)
        let httpServer = httpServers.removeValue(forKey: id)
        let vnc = vncSessions.removeValue(forKey: id)
        let rdp = rdpSessions.removeValue(forKey: id)

        serialTerm?.shutdown()
        DispatchQueue.global(qos: .utility).async {
            serial?.closePort()
            tcpClient?.disconnect()
            tcpServer?.stop()
            udp?.stop()
        }
        if let ssh {
            Task { await ssh.shutdown() }
        }
        if let sftp {
            Task { await sftp.shutdown() }
        }
        if let telnet {
            Task { await telnet.shutdown() }
        }
        agent?.shutdown()
        httpClient?.shutdown()
        httpServer?.stop()
        vnc?.shutdown()
        rdp?.shutdown()
        refreshRemoteActivity()
    }

    public func closeAllSessions() {
        let allIds = sessions.map { $0.id }
        for id in allIds {
            closeSession(id: id)
        }
        sessions.removeAll()
        activeSessionID = nil
        resetWorkspaceLayouts()
        refreshRemoteActivity()
    }

    private func refreshRemoteActivity() {
        let hasLiveRemote = sessions.contains { $0.type.usesAccountAuth && $0.isConnected }
        if hasLiveRemote {
            if remoteActivity == nil {
                remoteActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated, .automaticTerminationDisabled, .suddenTerminationDisabled],
                    reason: "Active remote sessions"
                )
            }
        } else if let remoteActivity {
            ProcessInfo.processInfo.endActivity(remoteActivity)
            self.remoteActivity = nil
        }
    }

    @discardableResult
    public func openAgentCLI(
        title: String,
        command: String,
        arguments: String?,
        workingDirectory: String?,
        environment: [String: String]?
    ) -> UUID {
        if let existing = sessions.first(where: {
            $0.type == .agentCLI
                && $0.host == command
                && $0.customCommand == arguments
                && ($0.workingDirectory ?? $0.targetDevice) == workingDirectory
        }) {
            selectSession(existing.id)
            return existing.id
        }
        let session = SessionItem(
            title: uniqueSessionTitle(title),
            subtitle: "\(command) \(arguments ?? "")",
            type: .agentCLI,
            isConnected: true,
            host: command,
            port: 0,
            targetDevice: workingDirectory,
            customCommand: arguments,
            workingDirectory: workingDirectory,
            environmentVariables: environment
        )
        let runtime = AgentCLISession(
            sessionID: session.id,
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environmentVariables: environment
        )
        agentCLISessions[session.id] = runtime
        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active
        revealSession(session.id)
        addRecent(RecentConnection(title: title, type: .agentCLI, host: command, port: 0))
        runtime.start()
        return session.id
    }

    public func addRecent(_ item: RecentConnection) {
        recentConnections.removeAll {
            $0.host == item.host
                && $0.port == item.port
                && $0.type == item.type
                && $0.accountID == item.accountID
        }
        recentConnections.insert(item, at: 0)
        if recentConnections.count > 20 {
            recentConnections = Array(recentConnections.prefix(20))
        }
        persistAll()
    }

    public func removeRecent(id: UUID) {
        recentConnections.removeAll { $0.id == id }
        persistAll()
    }

    public func clearAllRecent() {
        recentConnections.removeAll()
        persistAll()
    }

    private func persistAll() {
        ConfigStore.shared.saveAccounts(accounts)
        ConfigStore.shared.saveConnections(savedConnections)
        ConfigStore.shared.saveRecents(recentConnections)
    }

    private func loadData() {
        let store = ConfigStore.shared
        if store.fileExists("connections.json") || store.fileExists("accounts.json") || store.fileExists("recents.json") {
            accounts = store.loadAccounts()
            savedConnections = store.loadConnections()
            recentConnections = store.loadRecents()
        } else {
            migrateLegacyUserDefaults()
            persistAll()
        }
    }

    /// Keychain ACL prompt happens here, before splash is shown.
    public func unlockVault() {
        if isVaultReady { return }
        guard SecretStore.shared.unlock() else { return }
        migrateLegacySecretsIntoAccounts()
        isVaultReady = true
    }

    private func migrateLegacyUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: legacySavedKey),
           let decoded = try? JSONDecoder().decode([ConnectionConfig].self, from: data) {
            savedConnections = decoded
        }
        if let data = UserDefaults.standard.data(forKey: legacyRecentKey),
           let decoded = try? JSONDecoder().decode([RecentConnection].self, from: data) {
            recentConnections = decoded
        }
    }

    /// Old SSH connections stored secrets under the connection UUID. Promote those into accounts.
    private func migrateLegacySecretsIntoAccounts() {
        var changed = false
        for index in savedConnections.indices {
            let connection = savedConnections[index]
            guard connection.type.usesAccountAuth, connection.accountID == nil else { continue }
            let owner = connection.id
            let hasSecret = SecretStore.shared.hasAnySecret(accountID: owner)
            guard hasSecret || !connection.username.isEmpty else { continue }
            if account(id: owner) == nil {
                accounts.append(
                    AuthAccount(
                        id: owner,
                        name: connection.username.isEmpty ? connection.name : connection.username,
                        username: connection.username,
                        authMethod: connection.authMethod
                    )
                )
            }
            savedConnections[index].accountID = owner
            changed = true
        }
        if changed {
            persistAll()
        }
    }
}
