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
    public var telnetSessions: [UUID: TelnetTerminalSession] = [:]
    public var sshSessions: [UUID: SSHTerminalSession] = [:]
    public var sftpSessions: [UUID: SFTPBrowserSession] = [:]
    private var remoteActivity: NSObjectProtocol?

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
            let session = SessionItem(
                title: config.name,
                subtitle: "\(config.host) \(config.customArgs ?? "")",
                type: .agentCLI,
                isConnected: true,
                host: config.host,
                port: 0,
                targetDevice: config.workingDirectory,
                customCommand: config.customArgs,
                workingDirectory: config.workingDirectory,
                environmentVariables: config.envVars
            )
            sessions.append(session)
            activeSessionID = session.id
            sidebarTab = .active
            revealSession(session.id)
            addRecent(RecentConnection(title: config.name, type: .agentCLI, host: config.host, port: 0))
            return true
        }

        let result = openSession(
            type: config.type,
            host: config.host,
            port: config.port,
            title: config.name,
            username: resolvedUsername(for: config),
            connectionID: config.id,
            accountID: config.accountID
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
        forceNew: Bool = false
    ) -> Bool {
        if type == .vnc || type == .rdp {
            self.alertMessage = LocalizationManager.shared.text("feature_in_development_msg")
            return false
        }

        if !type.usesAccountAuth && !forceNew,
           let existing = sessions.first(where: { $0.type == type && $0.host == host && $0.port == port }) {
            selectSession(existing.id)
            return true
        }

        if type.usesAccountAuth {
            let matched = savedConnections.first(where: {
                $0.type == type && $0.host == host && $0.port == port
            })
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
                accountID: aid
            )
            beginRemoteConnect(config, saveOnSuccess: false)
            return true
        }

        if type == .serial {
            let available = SerialEngine.getAvailablePorts()
            if available.isEmpty {
                self.alertMessage = LocalizationManager.shared.text("no_serial_port_detected")
                return false
            }

            let targetPath = host.hasPrefix("/dev") ? host : available[0].path
            let baud = port > 1000 ? port : 115200
            let engine = SerialEngine()
            let opened = engine.openPort(path: targetPath, baud: baud)
            if !opened {
                self.alertMessage = "\(LocalizationManager.shared.text("serial_open_failed")) \(targetPath)"
                return false
            }

            let displayTitle = title ?? "Serial - \(targetPath.replacingOccurrences(of: "/dev/cu.", with: ""))"
            let session = SessionItem(
                title: displayTitle,
                subtitle: "\(baud) bps",
                type: .serial,
                isConnected: true,
                host: targetPath,
                port: baud,
                targetDevice: targetPath
            )
            serialEngines[session.id] = engine
            sessions.append(session)
            activeSessionID = session.id
            sidebarTab = .active
            revealSession(session.id)
            addRecent(RecentConnection(title: displayTitle, type: type, host: targetPath, port: baud, username: username))
            return true
        }

        let displayTitle = title ?? "\(type.rawValue) - \(host):\(port)"
        let session = SessionItem(
            title: displayTitle,
            subtitle: username != nil && !username!.isEmpty ? "\(username!)@\(host):\(port)" : "\(host):\(port)",
            type: type,
            isConnected: true,
            host: host,
            port: port
        )

        switch type {
        case .tcpClient:
            let engine = TCPClientEngine()
            engine.connect(host: host, port: port)
            tcpClientEngines[session.id] = engine
        case .tcpServer:
            let engine = TCPServerEngine()
            engine.start(port: port)
            tcpServerEngines[session.id] = engine
        case .udpTool:
            let engine = UDPEngine()
            engine.localPort = port
            engine.targetHost = host
            engine.targetPort = port
            engine.startListening()
            udpEngines[session.id] = engine
        case .httpClient, .agentCLI:
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

    public func saveConnection(_ config: ConnectionConfig, connectImmediately: Bool = true) {
        if let index = savedConnections.firstIndex(where: { $0.id == config.id }) {
            savedConnections[index] = config
        } else {
            savedConnections.insert(config, at: 0)
        }
        persistAll()

        if connectImmediately {
            if config.type.usesAccountAuth {
                beginRemoteConnect(config, saveOnSuccess: false)
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
        persistAll()
    }

    public func dismissConnectionHUD() {
        connectionHUD = nil
    }

    /// SSH / SFTP 共用账号密钥：先验证，成功后再按需保存连接。
    public func beginSSHConnect(_ config: ConnectionConfig, saveOnSuccess: Bool = false) {
        beginRemoteConnect(config, saveOnSuccess: saveOnSuccess)
    }

    public func beginRemoteConnect(_ config: ConnectionConfig, saveOnSuccess: Bool = false) {
        if let hud = connectionHUD, !hud.isFinished { return }
        guard config.type.usesAccountAuth else { return }
        if config.type == .vnc || config.type == .rdp {
            alertMessage = LocalizationManager.shared.text("feature_in_development_msg")
            return
        }
        guard let accountID = config.accountID, let account = account(id: accountID) else {
            alertMessage = LocalizationManager.shared.text("account_required")
            return
        }
        if account.kind.requiresUsername, account.username.isEmpty {
            alertMessage = LocalizationManager.shared.text("ssh_username_required")
            return
        }
        if account.kind.requiresSecret, !SecretStore.shared.hasAnySecret(accountID: accountID) {
            alertMessage = LocalizationManager.shared.text("ssh_credentials_required")
            return
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
        default: title = "Connecting"
        }
        let hud = ConnectionHUDState(title: title, subtitle: target)
        connectionHUD = hud
        if config.type == .telnet {
            Task { await runTelnetConnectPipeline(config: resolved, account: account, hud: hud, saveOnSuccess: saveOnSuccess) }
        } else {
            Task { await runRemoteConnectPipeline(config: resolved, account: account, hud: hud, saveOnSuccess: saveOnSuccess) }
        }
    }

    private func runTelnetConnectPipeline(
        config: ConnectionConfig,
        account: AuthAccount,
        hud: ConnectionHUDState,
        saveOnSuccess: Bool
    ) async {
        hud.log("Preparing Telnet session…")
        hud.log("Probing \(config.host):\(config.port)")
        let reachable = await SSHReachability.probe(host: config.host, port: config.port, timeout: 4)
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
            hud.log("Connecting (attempt \(attempt)/3)…")
            do {
                let connection = try await SSHReachability.withTimeout(seconds: 8) {
                    try await TelnetConnector.connect(host: config.host, port: config.port)
                }
                hud.log("Connected", kind: .success)
                hud.log("Opening terminal session…")
                if saveOnSuccess {
                    saveConnection(config, connectImmediately: false)
                    hud.log("Connection saved", kind: .success)
                }
                attachTelnetSession(config: config, connection: connection, password: password)
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
        saveOnSuccess: Bool
    ) async {
        hud.log(config.type == .sftp ? "Preparing SFTP session…" : "Preparing SSH session…")
        hud.log("Probing \(config.host):\(config.port)")
        let reachable = await SSHReachability.probe(host: config.host, port: config.port, timeout: 4)
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

        var lastError: Error = SSHConnectError.authFailed
        for attempt in 1...3 {
            hud.log("Authenticating (attempt \(attempt)/3)…")
            do {
                let client = try await SSHReachability.withTimeout(seconds: 8) {
                    var settings = SSHClientSettings(
                        host: host,
                        port: port,
                        authenticationMethod: {
                            (try? SSHAuthBuilder.makeMethod(
                                username: user,
                                password: password,
                                privateKeyPEM: privateKey,
                                keyPassphrase: passphrase
                            )) ?? .passwordBased(username: user, password: password ?? "")
                        },
                        hostKeyValidator: .acceptAnything()
                    )
                    settings.connectTimeout = .seconds(8)
                    return try await SSHClient.connect(to: settings)
                }
                hud.log("Authenticated", kind: .success)

                if config.type == .sftp {
                    do {
                        hud.log("Opening SFTP subsystem…")
                        let sftp = try await SSHReachability.withTimeout(seconds: 15) {
                            try await client.openSFTP()
                        }
                        hud.log("SFTP ready", kind: .success)
                        if saveOnSuccess {
                            saveConnection(config, connectImmediately: false)
                            hud.log("Connection saved", kind: .success)
                        }
                        attachSFTPSession(config: config, ssh: client, sftp: sftp)
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
                    attachSSHSession(config: config, client: client)
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

    private func attachSSHSession(config: ConnectionConfig, client: SSHClient) {
        let session = SessionItem(
            title: uniqueSessionTitle(config.name),
            subtitle: "\(config.username)@\(config.host):\(config.port)",
            type: .ssh,
            isConnected: true,
            host: config.host,
            port: config.port,
            customCommand: config.username,
            connectionID: config.id,
            accountID: config.accountID
        )
        let runtime = SSHTerminalSession(client: client, sessionID: session.id)
        sshSessions[session.id] = runtime
        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active
        revealSession(session.id)
        addRecent(RecentConnection(
            title: config.name,
            type: .ssh,
            host: config.host,
            port: config.port,
            username: config.username,
            accountID: config.accountID
        ))
        runtime.start()
        refreshRemoteActivity()
    }

    private func attachSFTPSession(config: ConnectionConfig, ssh: SSHClient, sftp: SFTPClient) {
        let session = SessionItem(
            title: uniqueSessionTitle(config.name),
            subtitle: "\(config.username)@\(config.host):\(config.port)",
            type: .sftp,
            isConnected: true,
            host: config.host,
            port: config.port,
            customCommand: config.username,
            connectionID: config.id,
            accountID: config.accountID
        )
        let browser = SFTPBrowserSession(ssh: ssh, sftp: sftp, sessionID: session.id)
        sftpSessions[session.id] = browser
        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active
        revealSession(session.id)
        addRecent(RecentConnection(
            title: config.name,
            type: .sftp,
            host: config.host,
            port: config.port,
            username: config.username,
            accountID: config.accountID
        ))
        browser.start()
        refreshRemoteActivity()
    }

    private func attachTelnetSession(config: ConnectionConfig, connection: NWConnection, password: String?) {
        let session = SessionItem(
            title: uniqueSessionTitle(config.name),
            subtitle: "\(config.username)@\(config.host):\(config.port)",
            type: .telnet,
            isConnected: true,
            host: config.host,
            port: config.port,
            customCommand: config.username,
            connectionID: config.id,
            accountID: config.accountID
        )
        let runtime = TelnetTerminalSession(
            connection: connection,
            sessionID: session.id,
            username: config.username,
            password: password
        )
        telnetSessions[session.id] = runtime
        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active
        revealSession(session.id)
        addRecent(RecentConnection(
            title: config.name,
            type: .telnet,
            host: config.host,
            port: config.port,
            username: config.username,
            accountID: config.accountID
        ))
        runtime.start()
        refreshRemoteActivity()
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
            let copy = SessionItem(
                title: uniqueSessionTitle(title),
                subtitle: session.subtitle,
                type: .agentCLI,
                isConnected: true,
                host: session.host,
                port: 0,
                targetDevice: session.targetDevice,
                customCommand: session.customCommand,
                workingDirectory: session.workingDirectory,
                environmentVariables: session.environmentVariables
            )
            sessions.append(copy)
            activeSessionID = copy.id
            sidebarTab = .active
            revealSession(copy.id)
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
            forceNew: true
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

    public func markSessionDisconnected(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].isConnected {
            sessions[index].isConnected = false
        }
        refreshRemoteActivity()
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
        let tcpClient = tcpClientEngines.removeValue(forKey: id)
        let tcpServer = tcpServerEngines.removeValue(forKey: id)
        let udp = udpEngines.removeValue(forKey: id)
        let ssh = sshSessions.removeValue(forKey: id)
        let sftp = sftpSessions.removeValue(forKey: id)
        let telnet = telnetSessions.removeValue(forKey: id)

        DispatchQueue.global(qos: .utility).async {
            serial?.closePort()
            tcpClient?.disconnect()
            tcpServer?.stop()
            udp?.stopListening()
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

    public func addRecent(_ item: RecentConnection) {
        recentConnections.removeAll { $0.host == item.host && $0.port == item.port && $0.type == item.type }
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
