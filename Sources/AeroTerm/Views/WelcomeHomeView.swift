import SwiftUI
import AppKit

public struct WelcomeHomeView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @State private var searchText = ""
    @State private var hoverRecentID: UUID? = nil
    @State private var isHoveringNewButton: Bool = false
    @State private var isViewAppeared: Bool = false

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
        VStack(spacing: 0) {
            Spacer().frame(height: 50)

            // 1. App Header Branding (入场微升淡入动画)
            HStack(spacing: 18) {
                appRealIconView
                    .frame(width: 68, height: 68)
                    .shadow(color: .black.opacity(isHoveringNewButton ? 0.24 : 0.16), radius: isHoveringNewButton ? 12 : 10, x: 0, y: isHoveringNewButton ? 6 : 5)
                    .scaleEffect(isHoveringNewButton ? 1.03 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHoveringNewButton)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(loc.text("app_title"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(loc.text("app_version"))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(loc.text("app_subtitle"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .offset(y: isViewAppeared ? 0 : 8)
            .opacity(isViewAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.28), value: isViewAppeared)

            Spacer().frame(height: 28)

            // 2. Primary Action: New Connection Wizard (带 Hover 微弹微光动画)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    sessionManager.isShowingNewConnectionWizard = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(loc.text("new_connection_btn"))
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 18)
                .frame(width: 380, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(isHoveringNewButton ? 0.18 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(isHoveringNewButton ? 0.45 : 0.25), lineWidth: 1)
                )
                .foregroundColor(.accentColor)
                .scaleEffect(isHoveringNewButton ? 1.015 : 1.0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: isViewAppeared ? 0 : 10)
            .opacity(isViewAppeared ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHoveringNewButton)
            .animation(.easeOut(duration: 0.32).delay(0.04), value: isViewAppeared)
            .onHover { isHovering in
                isHoveringNewButton = isHovering
            }

            Spacer().frame(height: 30)

            // 3. Recent Connections Section (带平滑过渡与过滤动效)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(loc.text("recent_connections"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    if !sessionManager.recentConnections.isEmpty {
                        Button(loc.text("clear_history")) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                sessionManager.clearAllRecent()
                            }
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary.opacity(0.8))
                    }
                }

                if sessionManager.recentConnections.count > 4 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        TextField(loc.text("filter_recents"), text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                    }
                    .padding(7)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .animation(.easeInOut(duration: 0.15), value: searchText)
                }

                // Recent List Container
                if filteredRecents.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(searchText.isEmpty ? loc.text("no_recent_history") : loc.text("no_matching_connections"))
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(8)
                    .transition(.opacity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(filteredRecents) { item in
                                recentRow(item: item)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 190)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: 600)
            .offset(y: isViewAppeared ? 0 : 12)
            .opacity(isViewAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.36).delay(0.08), value: isViewAppeared)
            .animation(.easeInOut(duration: 0.2), value: filteredRecents.count)

            // Bottom Breathing Spacer
            Spacer().frame(minHeight: 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            isViewAppeared = true
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
                    .cornerRadius(14)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(">_")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func recentRow(item: RecentConnection) -> some View {
        let isHovered = hoverRecentID == item.id

        return HStack(spacing: 12) {
            Image(systemName: item.type.iconName)
                .font(.system(size: 14))
                .foregroundColor(item.type.tintColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(item.host):\(item.port)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isHovered {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sessionManager.removeRecent(id: item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isHovered ? 0.08 : 0.0))
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = sessionManager.openSession(
                    type: item.type,
                    host: item.host,
                    port: item.port,
                    title: item.title,
                    username: item.username
                )
            }
        }
        .onHover { hovered in
            hoverRecentID = hovered ? item.id : nil
        }
    }
}
