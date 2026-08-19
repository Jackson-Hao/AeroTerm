import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SFTPToolView: View {
    let session: SessionItem
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    public init(session: SessionItem) {
        self.session = session
    }

    public var body: some View {
        Group {
            if let browser = sessionManager.sftpSessions[session.id], browser.isAlive {
                SFTPBrowserView(browser: browser, subtitle: session.subtitle)
                    .id(ObjectIdentifier(browser))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(loc.text("sftp_not_connected"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(loc.text("ssh_reconnect")) {
                        sessionManager.reconnect(session)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SFTPBrowserView: View {
    @ObservedObject var browser: SFTPBrowserSession
    let subtitle: String
    @ObservedObject var loc = LocalizationManager.shared

    @State private var selection: Set<SFTPRemoteEntry.ID> = []
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false

    private var sessionDragAwareTarget: Binding<Bool> {
        Binding(
            get: { isDropTargeted && PaneDragSession.activeSessionID == nil },
            set: { isDropTargeted = $0 && PaneDragSession.activeSessionID == nil }
        )
    }

    private var filteredEntries: [SFTPRemoteEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return browser.entries }
        return browser.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selectedEntries: [SFTPRemoteEntry] {
        filteredEntries.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            pathBar
            Divider()
            fileTable
            Divider()
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: sessionDragAwareTarget) { providers in
            guard PaneDragSession.activeSessionID == nil else { return false }
            return collectDroppedFiles(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.accentColor.opacity(0.08))
                    .padding(10)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 22, weight: .medium))
                            Text(loc.text("sftp_drop_upload"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .allowsHitTesting(false)
            }
        }
        .alert(loc.text("sftp_new_folder"), isPresented: $showNewFolder) {
            TextField(loc.text("sftp_folder_name"), text: $newFolderName)
            Button(loc.text("cancel"), role: .cancel) { newFolderName = "" }
            Button(loc.text("sftp_create")) {
                browser.createFolder(named: newFolderName)
                newFolderName = ""
            }
        }
        .alert(loc.text("sftp_rename"), isPresented: $showRename) {
            TextField(loc.text("sftp_new_name"), text: $renameText)
            Button(loc.text("cancel"), role: .cancel) {}
            Button(loc.text("sftp_rename_confirm")) {
                if let entry = selectedEntries.first {
                    browser.rename(entry, to: renameText)
                }
            }
        }
        .alert(loc.text("sftp_delete_title"), isPresented: $showDeleteConfirm) {
            Button(loc.text("cancel"), role: .cancel) {}
            Button(loc.text("sftp_delete"), role: .destructive) {
                browser.delete(selectedEntries)
                selection.removeAll()
            }
        } message: {
            Text(String(format: loc.text("sftp_delete_msg"), selectedEntries.count))
        }
        .alert(
            loc.text("alert_title"),
            isPresented: Binding(
                get: { browser.errorMessage != nil },
                set: { if !$0 { browser.errorMessage = nil } }
            )
        ) {
            Button(loc.text("ok"), role: .cancel) { browser.errorMessage = nil }
        } message: {
            Text(browser.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                browser.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!browser.canGoBack)
            .help(loc.text("sftp_back"))

            Button {
                browser.goUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(browser.currentPath == "/" || browser.currentPath.isEmpty)
            .help(loc.text("sftp_up"))

            Button {
                browser.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(browser.isBusy)
            .help(loc.text("sftp_refresh"))

            Divider().frame(height: 16)

            Button {
                pickUploads()
            } label: {
                Label(loc.text("sftp_upload"), systemImage: "arrow.up")
            }
            .disabled(browser.isTransferring)

            Button {
                browser.download(selectedEntries)
            } label: {
                Label(loc.text("sftp_download"), systemImage: "arrow.down")
            }
            .disabled(selectedEntries.isEmpty || browser.isTransferring)

            Button {
                newFolderName = ""
                showNewFolder = true
            } label: {
                Label(loc.text("sftp_new_folder"), systemImage: "folder.badge.plus")
            }

            Button {
                showDeleteConfirm = true
            } label: {
                Label(loc.text("sftp_delete"), systemImage: "trash")
            }
            .disabled(selectedEntries.isEmpty)

            Spacer()

            TextField(loc.text("sftp_search"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var pathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.cyan)
                    .font(.system(size: 11))
                ForEach(Array(SFTPPath.crumbs(for: browser.currentPath.isEmpty ? "/" : browser.currentPath).enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Button(crumb.title) {
                        browser.navigate(to: crumb.path)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                }
                if browser.isBusy && !browser.isTransferring {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
    }

    private var fileTable: some View {
        Table(filteredEntries, selection: $selection) {
            TableColumn(loc.text("sftp_col_name")) { entry in
                HStack(spacing: 7) {
                    Image(systemName: entry.iconName)
                        .foregroundStyle(entry.isDirectory ? Color.cyan : Color.secondary)
                        .frame(width: 14)
                    Text(entry.name)
                        .lineLimit(1)
                }
            }
            .width(min: 180, ideal: 280)

            TableColumn(loc.text("sftp_col_size")) { entry in
                Text(entry.sizeLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 88)

            TableColumn(loc.text("sftp_col_modified")) { entry in
                Text(entry.modifiedLabel)
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 160)

            TableColumn(loc.text("sftp_col_permissions")) { entry in
                Text(entry.permissionsLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu(forSelectionType: SFTPRemoteEntry.ID.self) { ids in
            let items = filteredEntries.filter { ids.contains($0.id) }
            if items.count == 1, let item = items.first, item.isDirectory {
                Button(loc.text("sftp_open")) { browser.open(item) }
            }
            Button(loc.text("sftp_download")) { browser.download(items) }
                .disabled(items.isEmpty)
            if items.count == 1 {
                Button(loc.text("sftp_rename")) {
                    renameText = items[0].name
                    showRename = true
                }
            }
            Divider()
            Button(loc.text("sftp_delete"), role: .destructive) {
                showDeleteConfirm = true
            }
            .disabled(items.isEmpty)
        } primaryAction: { ids in
            if ids.count == 1, let entry = filteredEntries.first(where: { $0.id == ids.first }) {
                browser.open(entry)
            }
        }
        .overlay {
            if filteredEntries.isEmpty && !browser.isBusy {
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.45))
                    Text(searchText.isEmpty ? loc.text("sftp_empty") : loc.text("sftp_no_match"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !selection.isEmpty {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(String(format: loc.text("sftp_selected_count"), selection.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let transfer = browser.transfer {
                Image(systemName: transfer.direction == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(transfer.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                ProgressView(value: transfer.fraction)
                    .frame(width: 120)
                Text(transfer.detailLabel)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                if transfer.fileCount > 1 {
                    Text("\(transfer.fileIndex)/\(transfer.fileCount)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button(loc.text("sftp_cancel_transfer")) {
                    browser.cancelTransfer()
                }
                .controlSize(.mini)
            } else {
                Text(browser.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
    }

    private func pickUploads() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = loc.text("sftp_upload")
        guard panel.runModal() == .OK else { return }
        browser.upload(localURLs: panel.urls)
    }

    private func collectDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                browser.upload(localURLs: urls)
            }
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let data = item as? NSData, let url = URL(dataRepresentation: data as Data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
