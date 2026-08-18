import SwiftUI
import AppKit

public struct XcodeStartupWindowView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    @State private var searchText = ""
    @State private var hoveredRecentID: UUID? = nil
    @State private var hoveredActionIndex: Int? = nil

    private var filteredRecents: [RecentConnection] {
        if searchText.isEmpty {
            return sessionManager.recentConnections
        } else {
            return sessionManager.recentConnections.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.host.localizedCaseInsensitiveContains(searchText) ||
                $0.type.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            // 1. 左侧主要品牌与三大功能操作区 (490px)
            leftBrandPane
                .frame(width: 490, height: 480)
                .background(Color(NSColor.windowBackgroundColor))

            // 2. 右侧高透晶莹毛玻璃最近连接栏 (290px，高通透质感)
            rightRecentPane
                .frame(width: 290, height: 480)
                .background(.ultraThinMaterial.opacity(0.75))
        }
        .frame(width: 780, height: 480)
        .contentShape(Rectangle())
    }

    // MARK: - 左侧品牌与三大无背景操作
    private var leftBrandPane: some View {
        VStack(spacing: 0) {
            // 顶部系统红灯自然留白
            Spacer().frame(height: 24)

            // 大号 Logo 图标 (140x140) + 超大范围 300x300 环境背光
            ZStack {
                // 超大范围环境光晕 (300x300, blur 32)
                RadialGradient(
                    colors: [
                        Color.blue.opacity(0.45),
                        Color.purple.opacity(0.28),
                        Color.cyan.opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 40,
                    endRadius: 150
                )
                .frame(width: 300, height: 300)
                .blur(radius: 32)

                // 140x140 高清大 Logo
                appRealIconView
                    .frame(width: 140, height: 140)
                    .shadow(color: .black.opacity(0.30), radius: 20, x: 0, y: 10)
            }
            .frame(height: 144)

            // 标题与版本
            VStack(spacing: 2) {
                Text(loc.text("app_title"))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Version 1.0 (Build 2026.1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            // 稍微下移间距 (加宽至 28px)
            Spacer().frame(height: 28)

            // 三大核心功能操作 (纯透明背景，仅悬浮微光)
            VStack(spacing: 8) {
                cleanActionRow(
                    index: 0,
                    icon: "plus.circle.fill",
                    color: .blue,
                    title: loc.text("create_new_conn_title"),
                    subtitle: loc.text("create_new_conn_subtitle")
                ) {
                    sessionManager.isShowingStartupSplash = false
                    sessionManager.isShowingNewConnectionWizard = true
                }

                cleanActionRow(
                    index: 1,
                    icon: "square.and.arrow.down.fill",
                    color: .orange,
                    title: loc.text("import_conn_title"),
                    subtitle: loc.text("import_conn_subtitle")
                ) {
                    handleImportConnections()
                }

                cleanActionRow(
                    index: 2,
                    icon: "macwindow",
                    color: .purple,
                    title: loc.text("open_workbench_title"),
                    subtitle: loc.text("open_workbench_subtitle")
                ) {
                    sessionManager.isShowingStartupSplash = false
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)
        }
    }

    // 纯透明无边框、稍微下移的操作条目 (仅 Hover 时有轻淡微光)
    private func cleanActionRow(
        index: Int,
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredActionIndex == index

        return Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(isHovered ? 0.22 : 0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isHovered ? .primary.opacity(0.8) : .secondary.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredActionIndex = hovering ? index : nil
        }
    }

    // MARK: - 右侧高透晶莹毛玻璃最近连接列表 (290px，高透材质)
    private var rightRecentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 高透窄版搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Filter recent...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(7)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // 最近记录内容
            if filteredRecents.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(searchText.isEmpty ? "No recent connections" : "No matching connections")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredRecents) { item in
                            narrowRecentRow(item: item)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func narrowRecentRow(item: RecentConnection) -> some View {
        let isHovered = hoveredRecentID == item.id

        return HStack(spacing: 9) {
            Image(systemName: item.type.iconName)
                .font(.system(size: 13.5))
                .foregroundColor(item.type.tintColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(item.host):\(item.port)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12.5))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.isShowingStartupSplash = false
            _ = sessionManager.openSession(
                type: item.type,
                host: item.host,
                port: item.port,
                title: item.title,
                username: item.username
            )
        }
        .onHover { hovering in
            hoveredRecentID = hovering ? item.id : nil
        }
    }

    private func handleImportConnections() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            sessionManager.importConnections(from: url)
            sessionManager.isShowingStartupSplash = false
        }
    }

    private var appRealIconView: some View {
        Group {
            if let img = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let img = NSImage(contentsOfFile: "/Users/jackson-hao/code/AeroTerm/Assets/AppIcon_1024.png") {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(28)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(">_")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
    }
}
