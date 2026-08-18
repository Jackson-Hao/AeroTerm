import SwiftUI

public struct SidebarView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @State private var hoveredActiveID: UUID? = nil
    @State private var hoveredSavedID: UUID? = nil

    public init() {}

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
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // 列表内容区 (根据二分按钮左右切换展示)
            Group {
                if sessionManager.sidebarTab == .saved {
                    savedConnectionsList
                } else {
                    activeSessionsList
                }
            }

            Divider()

            // 底部回到主页 (Home) 与设置入口
            bottomStatusBar
        }
        .background(.ultraThinMaterial.opacity(0.80))
        .sheet(isPresented: $sessionManager.isShowingNewConnectionWizard) {
            NewConnectionWizardView()
        }
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
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(sessionManager.savedConnections) { config in
                        savedConnectionRow(config: config)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func savedConnectionRow(config: ConnectionConfig) -> some View {
        let isCurrentlyOpen = sessionManager.sessions.contains { $0.host == config.host && $0.port == config.port && $0.type == config.type }
        let isCurrentlyActive = sessionManager.activeSession != nil && sessionManager.activeSession?.host == config.host && sessionManager.activeSession?.port == config.port && sessionManager.activeSession?.type == config.type

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

                Text(config.type == .serial ? "\(config.port) bps" : "\(config.host):\(config.port)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isCurrentlyOpen {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
            }

            if hoveredSavedID == config.id {
                Button {
                    sessionManager.deleteSavedConnection(id: config.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(loc.text("delete_config"))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hoveredSavedID == config.id ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.openFromConfig(config)
        }
        .onHover { isHovered in
            hoveredSavedID = isHovered ? config.id : nil
        }
        .contextMenu {
            Button(loc.text("start_connection")) {
                sessionManager.openFromConfig(config)
            }
            Divider()
            Button(loc.text("delete_config"), role: .destructive) {
                sessionManager.deleteSavedConnection(id: config.id)
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
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(sessionManager.sessions) { session in
                        activeSessionRow(session: session)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func activeSessionRow(session: SessionItem) -> some View {
        let isSelected = sessionManager.activeSessionID == session.id

        return HStack(spacing: 8) {
            Circle()
                .fill(session.isConnected ? Color.green : Color.yellow)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))
                    .lineLimit(1)

                Text("\(session.host):\(session.port)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if hoveredActiveID == session.id || isSelected {
                Button {
                    sessionManager.closeSession(id: session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .background(Color.secondary.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(loc.text("close_session"))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : (hoveredActiveID == session.id ? Color.secondary.opacity(0.08) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.activeSessionID = session.id
        }
        .onHover { isHovered in
            hoveredActiveID = isHovered ? session.id : nil
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
                        .foregroundColor(sessionManager.activeSessionID == nil ? .accentColor : .secondary)
                    Text(loc.text("welcome_home"))
                        .font(.system(size: 11, weight: sessionManager.activeSessionID == nil ? .semibold : .regular))
                        .foregroundColor(sessionManager.activeSessionID == nil ? .primary : .secondary)
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
        .background(.ultraThinMaterial.opacity(0.60))
    }
}
