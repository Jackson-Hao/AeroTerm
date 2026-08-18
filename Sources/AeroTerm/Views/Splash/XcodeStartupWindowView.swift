import SwiftUI
import AppKit

/// Xcode Welcome 风格启动窗。
/// 左侧较大：品牌信息与入口选择（半透明，透明度较低）。
/// 右侧较小：最近连接历史（更高透）。
/// 不使用系统 Titlebar；左上角自定义关闭红灯。
public struct XcodeStartupWindowView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    @State private var searchText = ""
    @State private var hoveredActionIndex: Int?
    @State private var hoveredRecentID: UUID?
    @State private var isFilterFocused: Bool = false
    @State private var isCloseHovered: Bool = false

    private let rightWidth: CGFloat = 268
    private let actionColumnWidth: CGFloat = 336

    private var filteredRecents: [RecentConnection] {
        let recents = sessionManager.recentConnections
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recents }
        return recents.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.host.localizedCaseInsensitiveContains(query) ||
            $0.type.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    public init() {}

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // 整窗一层连续模糊，避免底边、圆角和中缝漏出纯透明桌面
            windowBackdrop

            HStack(spacing: 0) {
                leftInfoPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 1)
                    .padding(.vertical, 0)

                rightHistoryPane
                    .frame(width: rightWidth)
                    .frame(maxHeight: .infinity)
            }

            customCloseButton
                .padding(.leading, 14)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Backdrop（单层铺满，左右只叠遮罩）

    private var windowBackdrop: some View {
        ZStack {
            AppBackdrop(material: .sidebar)

            HStack(spacing: 0) {
                Color(NSColor.windowBackgroundColor).opacity(0.10)
                Color.clear
                    .frame(width: rightWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var customCloseButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.36, blue: 0.34))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    )

                if isCloseHovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Color(red: 0.30, green: 0.02, blue: 0.02))
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovered = $0 }
        .help(loc.text("close"))
    }

    // MARK: - 左侧：信息与选择

    private var leftInfoPane: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 44)

            appIconView
                .frame(width: 148, height: 148)
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)

            VStack(spacing: 4) {
                Text(loc.text("welcome_window_title"))
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Version alpha-0818")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 2) {
                actionRow(
                    index: 0,
                    icon: "plus.rectangle",
                    title: loc.text("create_new_conn_title"),
                    subtitle: loc.text("create_new_conn_subtitle")
                ) {
                    sessionManager.isShowingNewConnectionWizard = true
                }

                actionRow(
                    index: 1,
                    icon: "square.and.arrow.down",
                    title: loc.text("import_conn_title"),
                    subtitle: loc.text("import_conn_subtitle")
                ) {
                    handleImportConnections()
                }

                actionRow(
                    index: 2,
                    icon: "folder",
                    title: loc.text("open_workbench_title"),
                    subtitle: loc.text("open_workbench_subtitle")
                ) {
                    sessionManager.enterWorkbench()
                }
            }
            .frame(width: actionColumnWidth, alignment: .leading)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func actionRow(
        index: Int,
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredActionIndex == index

        return Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredActionIndex = hovering ? index : nil
        }
    }

    // MARK: - 右侧：历史记录

    private var rightHistoryPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterField
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if filteredRecents.isEmpty {
                emptyHistory
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredRecents) { item in
                            historyRow(item: item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(loc.text("filter_recents"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .onSubmit {
                    openFirstFilteredRecent()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isFilterFocused ? 0.08 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(isFilterFocused ? 0.14 : 0.06), lineWidth: 1)
        )
        .onHover { hovering in
            isFilterFocused = hovering
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary.opacity(0.35))
            Text(searchText.isEmpty ? loc.text("no_recent_history") : loc.text("no_matching_connections"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func historyRow(item: RecentConnection) -> some View {
        let isHovered = hoveredRecentID == item.id

        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(item.type.tintColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(recentSubtitle(item))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openRecent(item)
            }

            if isHovered {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sessionManager.removeRecent(id: item.id)
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredRecentID = hovering ? item.id : nil
        }
        .contextMenu {
            Button(loc.text("start_connection")) {
                openRecent(item)
            }
        }
    }

    // MARK: - Actions

    private func recentSubtitle(_ item: RecentConnection) -> String {
        if item.type == .serial {
            return "\(item.host)  \(item.port) bps"
        }
        if item.type == .agentCLI {
            return item.host
        }
        return "\(item.host):\(item.port)"
    }

    private func openRecent(_ item: RecentConnection) {
        let opened = sessionManager.openSession(
            type: item.type,
            host: item.host,
            port: item.port,
            title: item.title,
            username: item.username,
            accountID: item.accountID
        )
        if opened {
            sessionManager.enterWorkbench()
        }
    }

    private func openFirstFilteredRecent() {
        guard let first = filteredRecents.first else { return }
        openRecent(first)
    }

    private func handleImportConnections() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            if sessionManager.importConnections(from: url) {
                sessionManager.enterWorkbench()
            }
        }
    }

    private var appIconView: some View {
        Group {
            if let image = resolvedAppIcon() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.22, green: 0.48, blue: 0.96),
                                    Color(red: 0.36, green: 0.28, blue: 0.86)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(">_")
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func resolvedAppIcon() -> NSImage? {
        if let image = NSImage(named: NSImage.applicationIconName), image.size.width > 16 {
            return image
        }
        let candidates = [
            Bundle.main.url(forResource: "AppIcon_1024", withExtension: "png"),
            Bundle.module.url(forResource: "AppIcon_1024", withExtension: "png")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}
