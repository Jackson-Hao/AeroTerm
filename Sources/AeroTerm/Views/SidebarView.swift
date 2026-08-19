import SwiftUI

public struct SidebarView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @State private var hoveredActiveID: UUID? = nil
    @State private var hoveredSavedID: UUID? = nil
    @State private var isShowingConnectionManager = false
    @State private var editingConnectionID: UUID? = nil

    public init() {}

    private var isHomeSelected: Bool {
        sessionManager.activeSessionID == nil && sessionManager.primarySurface.layout == nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部原生二分切换器 (Saved | Active)
            Picker("", selection: $sessionManager.sidebarTab) {
                Text("\(loc.text("saved_tab"))\(sessionManager.savedConnections.isEmpty ? "" : " (\(sessionManager.savedConnections.count))")")
                    .tag(SidebarTab.saved)
                Text("\(loc.text("active_tab"))\(sessionManager.sessions.isEmpty ? "" : " (\(sessionManager.sessions.count))")")
                    .tag(SidebarTab.active)
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // 列表内容区 (采用稳定的 ZStack 避免切换时的尺寸突变和 UI 异常)
            ZStack {
                savedConnectionsList
                    .opacity(sessionManager.sidebarTab == .saved ? 1 : 0)
                    .allowsHitTesting(sessionManager.sidebarTab == .saved)

                activeSessionsList
                    .opacity(sessionManager.sidebarTab == .active ? 1 : 0)
                    .allowsHitTesting(sessionManager.sidebarTab == .active)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.12), value: sessionManager.sidebarTab)

            Divider()

            // 底部回到主页 (Home) 与设置入口
            bottomStatusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AppBackdrop(material: .sidebar)
                .ignoresSafeArea(edges: .top)
        }
        .sheet(isPresented: $sessionManager.isShowingNewConnectionWizard) {
            NewConnectionWizardView()
        }
        .sheet(isPresented: $isShowingConnectionManager) {
            ConnectionManagerSheet(initialSelection: editingConnectionID)
        }
        .onChange(of: sessionManager.sidebarTab) { _, _ in
            hoveredActiveID = nil
            hoveredSavedID = nil
        }
    }

    private func activeSessionSubtitle(_ session: SessionItem) -> String {
        if session.type == .httpClient {
            return session.label.isEmpty ? session.subtitle : session.label
        }
        if session.type == .serial {
            let device = session.host.replacingOccurrences(of: "/dev/cu.", with: "")
            if device.isEmpty {
                return "\(loc.text(session.serial.mode.titleKey)) · \(String(session.port)) \(session.serial.lineSpec)"
            }
            return "\(loc.text(session.serial.mode.titleKey)) · \(device) @ \(String(session.port))"
        }
        if session.type == .udpTool {
            return "\(session.udpMode.title) \(session.host):\(String(session.port))"
        }
        return "\(session.host):\(String(session.port))"
    }

    private func localPortLine(_ port: Int) -> String {
        if port > 0 {
            return String(format: loc.text("tcp_local_line"), String(port))
        }
        return loc.text("tcp_local_auto")
    }

    private func savedConnectionSubtitle(_ config: ConnectionConfig) -> String {
        if config.type == .httpClient {
            return config.label.isEmpty ? config.type.rawValue : config.label
        }
        if config.type == .serial {
            let device = config.host.replacingOccurrences(of: "/dev/cu.", with: "")
            if device.isEmpty {
                return "\(loc.text(config.serial.mode.titleKey)) · \(String(config.port)) \(config.serial.lineSpec)"
            }
            return "\(loc.text(config.serial.mode.titleKey)) · \(device) @ \(String(config.port))"
        }
        if config.type == .udpTool {
            return "\(config.udpMode.title) \(config.host):\(String(config.port))"
        }
        let user = sessionManager.resolvedUsername(for: config)
        if config.type.usesAccountAuth && !user.isEmpty {
            return "\(user)@\(config.host):\(config.port)"
        }
        return "\(config.host):\(config.port)"
    }

    // MARK: - 1. 已保存连接列表 (Saved Connections)
    private var savedConnectionsList: some View {
        Group {
            if sessionManager.savedConnections.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(loc.text("no_saved_connections"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button(loc.text("create_connection_now")) {
                        sessionManager.isShowingNewConnectionWizard = true
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(sessionManager.savedConnections) { config in
                            savedConnectionRow(config: config)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func savedConnectionRow(config: ConnectionConfig) -> some View {
        let isCurrentlyOpen = sessionManager.sessions.contains { $0.host == config.host && $0.port == config.port && $0.type == config.type }
        let isCurrentlyActive = sessionManager.activeSession != nil && sessionManager.activeSession?.host == config.host && sessionManager.activeSession?.port == config.port && sessionManager.activeSession?.type == config.type
        let isHovered = hoveredSavedID == config.id

        return HStack(spacing: 8) {
            Image(systemName: config.type.iconName)
                .font(.system(size: 12))
                .foregroundColor(config.type.tintColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 12, weight: isCurrentlyActive ? .semibold : .regular))
                    .foregroundColor(isCurrentlyActive ? .primary : .primary.opacity(0.85))
                    .lineLimit(1)

                Text(savedConnectionSubtitle(config))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if config.type == .tcpClient || config.type == .udpTool || config.type == .httpServer {
                    Text(verbatim: localPortLine(config.localPort))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if config.type == .serial {
                    Text(verbatim: "\(String(config.port)) \(config.serial.detailLabel)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isCurrentlyOpen {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
            }

            if isHovered {
                Button {
                    sessionManager.requestDeleteConnection(id: config.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(loc.text("delete_config"))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.openFromConfig(config)
        }
        .onHover { hovered in
            hoveredSavedID = hovered ? config.id : nil
        }
        .contextMenu {
            Button(loc.text("start_connection")) {
                sessionManager.openFromConfig(config)
            }
            Button(loc.text("edit_config")) {
                editingConnectionID = config.id
                isShowingConnectionManager = true
            }
            Divider()
            Button(loc.text("delete_config"), role: .destructive) {
                sessionManager.requestDeleteConnection(id: config.id)
            }
        }
    }

    // MARK: - 2. 当前连接列表 (Active Sessions)
    private var activeSessionsList: some View {
        Group {
            if sessionManager.sessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(loc.text("no_active_sessions"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button(loc.text("launch_from_saved")) {
                        sessionManager.sidebarTab = .saved
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(sessionManager.sessions) { session in
                            activeSessionRow(session: session)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeSessionRow(session: SessionItem) -> some View {
        let isSelected = sessionManager.activeSessionID == session.id
        let isHovered = hoveredActiveID == session.id

        return HStack(spacing: 8) {
            Circle()
                .fill(session.indicatorColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))
                    .lineLimit(1)

                Text(verbatim: activeSessionSubtitle(session))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if session.type == .tcpClient || session.type == .udpTool || session.type == .httpServer {
                    Text(verbatim: localPortLine(session.localPort))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if session.type == .serial {
                    Text(verbatim: "\(String(session.port)) \(session.serial.detailLabel)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if sessionManager.isSessionDetached(session.id) {
                Image(systemName: "macwindow")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .help(loc.text("session_pop_out"))
            }

            if isHovered || isSelected {
                Button {
                    sessionManager.requestCloseSession(id: session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .background(Color.secondary.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(loc.text("close_session"))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.selectSession(session.id)
        }
        .onHover { hovered in
            hoveredActiveID = hovered ? session.id : nil
        }
        .onDrag {
            SessionDragPayload.provider(for: session.id)
        }
        .contextMenu {
            Button {
                sessionManager.duplicateSession(session)
            } label: {
                Label(loc.text("session_duplicate"), systemImage: "plus.square.on.square")
            }

            Button {
                sessionManager.toggleSessionSuspended(id: session.id)
            } label: {
                Label(
                    session.isSuspended ? loc.text("session_resume") : loc.text("session_suspend"),
                    systemImage: session.isSuspended ? "play.circle.fill" : "pause.circle.fill"
                )
            }
            .foregroundStyle(session.isSuspended ? Color.green : Color.yellow)

            Divider()

            if sessionManager.isSessionDetached(session.id) {
                Button {
                    sessionManager.mergeSessionToMain(session.id)
                } label: {
                    Label(loc.text("session_merge_main"), systemImage: "rectangle.badge.arrow.left")
                }
            } else {
                Button {
                    sessionManager.detachSession(session.id)
                } label: {
                    Label(loc.text("session_pop_out"), systemImage: "macwindow")
                }
            }

            Button {
                sessionManager.splitSession(session.id, axis: .horizontal)
            } label: {
                Label(loc.text("session_split_right"), systemImage: "rectangle.split.2x1")
            }

            Button {
                sessionManager.splitSession(session.id, axis: .vertical)
            } label: {
                Label(loc.text("session_split_down"), systemImage: "rectangle.split.1x2")
            }

            Divider()

            Button(role: .destructive) {
                sessionManager.requestCloseSession(id: session.id)
            } label: {
                Label(loc.text("session_close"), systemImage: "xmark.circle.fill")
            }
            .foregroundStyle(Color.red)
        }
    }

    // 底部主页与设置入口 (Home)
    private var bottomStatusBar: some View {
        HStack(spacing: 6) {
            Button {
                sessionManager.activeSessionID = nil
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(isHomeSelected ? .accentColor : .secondary)
                    Text(loc.text("welcome_home"))
                        .font(.system(size: 11, weight: isHomeSelected ? .semibold : .regular))
                        .foregroundColor(isHomeSelected ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 设置按钮 (⌘,)
            Button {
                settingsManager.isShowingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(loc.text("settings_title") + " (⌘,)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}
