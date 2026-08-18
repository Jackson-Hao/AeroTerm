import Foundation
import SwiftUI
import AppKit
import Combine

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
    
    @Published public var savedConnections: [ConnectionConfig] = []
    @Published public var sessions: [SessionItem] = []
    @Published public var activeSessionID: UUID? = nil
    @Published public var recentConnections: [RecentConnection] = []
    @Published public var alertMessage: String? = nil

    // Dedicated tool engines per tab session
    public var tcpClientEngines: [UUID: TCPClientEngine] = [:]
    public var tcpServerEngines: [UUID: TCPServerEngine] = [:]
    public var udpEngines: [UUID: UDPEngine] = [:]
    public var serialEngines: [UUID: SerialEngine] = [:]
    public var telnetEngines: [UUID: TelnetEngine] = [:]

    private let savedKey = "AeroTerm.SavedConnections.v5"
    private let recentKey = "AeroTerm.RecentConnections.v5"

    public init() {
        self.isShowingStartupSplash = true
        loadData()
        setupFullScreenObserver()
    }

    private func setupFullScreenObserver() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isFullScreen = true
                self?.columnVisibility = .detailOnly
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isFullScreen = false
                self?.columnVisibility = .all
            }
        }
    }

    public var activeSession: SessionItem? {
        guard let activeSessionID = activeSessionID else { return nil }
        return sessions.first(where: { $0.id == activeSessionID })
    }

    public func showWizard(defaultType: SessionType? = nil) {
        isShowingStartupSplash = false
        isShowingNewConnectionWizard = true
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
            addRecent(RecentConnection(title: config.name, type: .agentCLI, host: config.host, port: 0))
            return true
        }

        let result = openSession(
            type: config.type,
            host: config.host,
            port: config.port,
            title: config.name,
            username: config.username
        )
        if result {
            sidebarTab = .active
        }
        return result
    }

    @discardableResult
    public func openSession(type: SessionType, host: String = "127.0.0.1", port: Int = 22, title: String? = nil, username: String? = nil) -> Bool {
        if type == .ssh || type == .sftp || type == .vnc || type == .rdp {
            self.alertMessage = LocalizationManager.shared.text("feature_in_development_msg")
            return false
        }

        if let existing = sessions.first(where: { $0.type == type && $0.host == host && $0.port == port }) {
            activeSessionID = existing.id
            sidebarTab = .active
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
        case .telnet:
            let engine = TelnetEngine()
            engine.connect(host: host, port: port)
            telnetEngines[session.id] = engine
        case .httpClient, .agentCLI:
            break
        case .ssh, .sftp, .vnc, .rdp, .serial:
            break
        }

        sessions.append(session)
        activeSessionID = session.id
        sidebarTab = .active

        addRecent(RecentConnection(title: displayTitle, type: type, host: host, port: port, username: username))
        return true
    }

    public func saveConnection(_ config: ConnectionConfig, connectImmediately: Bool = true) {
        if let index = savedConnections.firstIndex(where: { $0.id == config.id }) {
            savedConnections[index] = config
        } else {
            savedConnections.insert(config, at: 0)
        }
        saveData()

        if connectImmediately {
            openFromConfig(config)
        }
    }

    public func importConnections(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if let decoded = try? JSONDecoder().decode([ConnectionConfig].self, from: data) {
                for item in decoded {
                    saveConnection(item, connectImmediately: false)
                }
                self.alertMessage = "\(LocalizationManager.shared.text("import_success")) (\(decoded.count))"
            } else {
                self.alertMessage = LocalizationManager.shared.text("import_failed")
            }
        } catch {
            self.alertMessage = "\(LocalizationManager.shared.text("import_failed")): \(error.localizedDescription)"
        }
    }

    public func deleteSavedConnection(id: UUID) {
        savedConnections.removeAll { $0.id == id }
        saveData()
    }

    public func closeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

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
        let telnet = telnetEngines.removeValue(forKey: id)

        DispatchQueue.global(qos: .utility).async {
            serial?.closePort()
            tcpClient?.disconnect()
            tcpServer?.stop()
            udp?.stopListening()
            telnet?.disconnect()
        }
    }

    public func closeAllSessions() {
        let allIds = sessions.map { $0.id }
        for id in allIds {
            closeSession(id: id)
        }
        sessions.removeAll()
        activeSessionID = nil
    }

    public func addRecent(_ item: RecentConnection) {
        recentConnections.removeAll { $0.host == item.host && $0.port == item.port && $0.type == item.type }
        recentConnections.insert(item, at: 0)
        if recentConnections.count > 20 {
            recentConnections = Array(recentConnections.prefix(20))
        }
        saveData()
    }

    public func removeRecent(id: UUID) {
        recentConnections.removeAll { $0.id == id }
        saveData()
    }

    public func clearAllRecent() {
        recentConnections.removeAll()
        saveData()
    }

    private func saveData() {
        if let encoded = try? JSONEncoder().encode(savedConnections) {
            UserDefaults.standard.set(encoded, forKey: savedKey)
        }
        if let encoded = try? JSONEncoder().encode(recentConnections) {
            UserDefaults.standard.set(encoded, forKey: recentKey)
        }
    }

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: savedKey),
           let decoded = try? JSONDecoder().decode([ConnectionConfig].self, from: data) {
            self.savedConnections = decoded
        }
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let decoded = try? JSONDecoder().decode([RecentConnection].self, from: data) {
            self.recentConnections = decoded
        }
    }
}
