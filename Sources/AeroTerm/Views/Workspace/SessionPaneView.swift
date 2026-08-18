import SwiftUI
import AppKit

struct SessionPaneHeaderView: View {
    let nodeID: UUID
    let surfaceID: UUID
    let sessionID: UUID?

    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    private var session: SessionItem? {
        guard let sessionID else { return nil }
        return sessionManager.sessions.first(where: { $0.id == sessionID })
    }

    private var isFocused: Bool {
        sessionManager.focusedSurfaceID == surfaceID
            && sessionManager.surface(id: surfaceID)?.focusedNodeID == nodeID
    }

    var body: some View {
        HStack(spacing: 6) {
            if let session {
                Image(systemName: session.type.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(session.type.tintColor)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 11, weight: isFocused ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !session.subtitle.isEmpty, session.subtitle != session.title {
                        Text(session.subtitle)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(loc.text("pane_empty_title"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 4) {
                if let session {
                    paneMenu(session: session)
                }
                Button {
                    sessionManager.closePane(nodeID: nodeID, surfaceID: surfaceID)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.secondary.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(loc.text("pane_close"))
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .contentShape(Rectangle())
        .modifier(SessionDragSource(sessionID: sessionID))
        .onTapGesture {
            sessionManager.focusPane(nodeID: nodeID, surfaceID: surfaceID)
        }
    }

    @ViewBuilder
    private func paneMenu(session: SessionItem) -> some View {
        Menu {
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 16, height: 16)
    }
}

struct SessionPaneBodyView: View {
    let nodeID: UUID
    let surfaceID: UUID
    let sessionID: UUID?

    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    private var session: SessionItem? {
        guard let sessionID else { return nil }
        return sessionManager.sessions.first(where: { $0.id == sessionID })
    }

    var body: some View {
        ZStack {
            if let session {
                SessionContentView(session: session)
                    .id(session.id)
                if session.isSuspended {
                    suspendedOverlay(for: session)
                }
            } else {
                emptyPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.focusPane(nodeID: nodeID, surfaceID: surfaceID)
        }
    }

    private var emptyPane: some View {
        let candidates = sessionManager.hiddenSessions(excluding: surfaceID)
        return VStack(spacing: 10) {
            Image(systemName: "rectangle.badge.plus")
                .font(.system(size: 22))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(loc.text("pane_drop_hint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates.prefix(6)) { item in
                        Button {
                            sessionManager.assignSessionToLeaf(item.id, nodeID: nodeID, surfaceID: surfaceID)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.type.iconName)
                                    .foregroundStyle(item.type.tintColor)
                                Text(item.title)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func suspendedOverlay(for session: SessionItem) -> some View {
        ZStack {
            Color.black.opacity(0.28)
            VStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.yellow)
                Text(loc.text("session_suspended_title"))
                    .font(.system(size: 14, weight: .semibold))
                Text(session.title)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(loc.text("session_resume")) {
                    sessionManager.setSessionSuspended(id: session.id, false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
