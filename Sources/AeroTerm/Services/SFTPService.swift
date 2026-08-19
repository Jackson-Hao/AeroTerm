import Foundation
import AppKit
import Combine
@preconcurrency import Citadel
import NIOCore

public enum SFTPRemoteKind: String, Sendable {
    case directory
    case file
    case symlink
}

public enum SFTPTransferDirection: String, Sendable {
    case upload
    case download
}

public struct SFTPRemoteEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let kind: SFTPRemoteKind
    public let size: UInt64?
    public let modified: Date?
    public let permissions: UInt32?
    public let longname: String

    public var isDirectory: Bool { kind == .directory }

    public var iconName: String {
        switch kind {
        case .directory: return "folder.fill"
        case .symlink: return "link"
        case .file: return Self.fileIcon(for: name)
        }
    }

    public var sizeLabel: String {
        guard !isDirectory, let size else { return "—" }
        return SFTPFormatting.bytes(size)
    }

    public var modifiedLabel: String {
        guard let modified else { return "—" }
        return SFTPFormatting.date(modified)
    }

    public var permissionsLabel: String {
        SFTPFormatting.unixMode(permissions, kind: kind)
    }

    private static func fileIcon(for name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "heic":
            return "photo"
        case "mp4", "mov", "mkv", "avi", "webm":
            return "film"
        case "mp3", "wav", "flac", "aac", "m4a":
            return "music.note"
        case "zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "xz":
            return "doc.zipper"
        case "swift", "c", "h", "cc", "cpp", "m", "mm", "rs", "go", "py", "js", "ts", "java":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "txt", "log", "json", "yml", "yaml", "toml", "xml", "csv":
            return "doc.text"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }
}

public struct SFTPTransferProgress: Equatable, Sendable {
    public var fileName: String
    public var direction: SFTPTransferDirection
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var fileIndex: Int
    public var fileCount: Int

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    public var detailLabel: String {
        let current = SFTPFormatting.bytes(UInt64(max(0, completedBytes)))
        if totalBytes > 0 {
            return "\(current) / \(SFTPFormatting.bytes(UInt64(totalBytes)))"
        }
        return current
    }
}

public enum SFTPFormatting {
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(value)
        var index = 0
        while size >= 1024, index < units.count - 1 {
            size /= 1024
            index += 1
        }
        if index == 0 {
            return "\(value) B"
        }
        return String(format: "%.1f %@", size, units[index])
    }

    public static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    public static func unixMode(_ permissions: UInt32?, kind: SFTPRemoteKind) -> String {
        let prefix: String
        switch kind {
        case .directory: prefix = "d"
        case .symlink: prefix = "l"
        case .file: prefix = "-"
        }
        guard let permissions else { return prefix + "?????????" }
        let mode = permissions & 0o777
        return prefix + triad(mode >> 6) + triad(mode >> 3) + triad(mode)
    }

    private static func triad(_ bits: UInt32) -> String {
        let value = bits & 0o7
        return "\(value & 4 != 0 ? "r" : "-")\(value & 2 != 0 ? "w" : "-")\(value & 1 != 0 ? "x" : "-")"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

enum SFTPPath {
    static func join(_ base: String, _ name: String) -> String {
        if name.hasPrefix("/") { return name }
        if base == "/" { return "/\(name)" }
        if base.hasSuffix("/") { return base + name }
        return "\(base)/\(name)"
    }

    static func parent(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let slash = trimmed.lastIndex(of: "/") else { return "/" }
        let parent = String(trimmed[..<slash])
        return parent.isEmpty ? "/" : parent
    }

    static func crumbs(for path: String) -> [(title: String, path: String)] {
        if path == "/" { return [("/", "/")] }
        var items: [(String, String)] = [("/", "/")]
        var built = ""
        for part in path.split(separator: "/") where !part.isEmpty {
            built += "/\(part)"
            items.append((String(part), built))
        }
        return items
    }
}

private enum SFTPFileType {
    static let mask: UInt32 = 0o170000
    static let directory: UInt32 = 0o040000
    static let symlink: UInt32 = 0o120000

    static func kind(attributes: SFTPFileAttributes, longname: String) -> SFTPRemoteKind {
        if let permissions = attributes.permissions {
            let type = permissions & mask
            if type == directory { return .directory }
            if type == symlink { return .symlink }
            if type != 0 { return .file }
        }
        if longname.hasPrefix("d") { return .directory }
        if longname.hasPrefix("l") { return .symlink }
        return .file
    }
}

private let sftpChunkSize = 32_000

private final class FileHandleBox: @unchecked Sendable {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    func close() { try? handle.close() }
}

@MainActor
public final class SFTPBrowserSession: ObservableObject {
    @Published public var currentPath: String = ""
    @Published public var entries: [SFTPRemoteEntry] = []
    @Published public var isBusy: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var errorMessage: String?
    @Published public var transfer: SFTPTransferProgress?
    @Published public var canGoBack: Bool = false
    @Published public var isAlive: Bool = true

    private let ssh: SSHClient
    private let sftp: SFTPClient
    public let sessionID: UUID
    private var pathHistory: [String] = []
    private var transferTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var listGeneration: UInt64 = 0
    private var shuttingDown = false

    public init(ssh: SSHClient, sftp: SFTPClient, sessionID: UUID) {
        self.ssh = ssh
        self.sftp = sftp
        self.sessionID = sessionID
        ssh.onDisconnect { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect()
            }
        }
    }

    public var isTransferring: Bool { transfer != nil && transferTask != nil }

    public func start() {
        startKeepAlive()
        Task { await resolveHomeAndList() }
    }

    public func refresh() {
        Task { await listCurrent() }
    }

    public func navigate(to path: String, recordHistory: Bool = true) {
        let target = path.isEmpty ? "/" : path
        if target == currentPath {
            Task { await listCurrent() }
            return
        }
        Task { await listAndCommit(target, recordHistory: recordHistory) }
    }

    public func goBack() {
        guard let previous = pathHistory.last else { return }
        Task {
            let ok = await listAndCommit(previous, recordHistory: false)
            if ok {
                _ = pathHistory.popLast()
                canGoBack = !pathHistory.isEmpty
            }
        }
    }

    public func goUp() {
        guard currentPath != "/", !currentPath.isEmpty else { return }
        navigate(to: SFTPPath.parent(currentPath))
    }

    public func open(_ entry: SFTPRemoteEntry) {
        if entry.isDirectory {
            navigate(to: entry.path)
        } else {
            download([entry])
        }
    }

    public func createFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeName(name) else {
            errorMessage = LocalizationManager.shared.text("sftp_invalid_name")
            return
        }
        let path = SFTPPath.join(currentPath, name)
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await sftp.createDirectory(atPath: path)
                statusMessage = LocalizationManager.shared.text("sftp_folder_created")
                await listCurrent()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func rename(_ entry: SFTPRemoteEntry, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeName(name), name != entry.name else {
            if name != entry.name {
                errorMessage = LocalizationManager.shared.text("sftp_invalid_name")
            }
            return
        }
        let dest = SFTPPath.join(SFTPPath.parent(entry.path), name)
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await sftp.rename(at: entry.path, to: dest)
                statusMessage = LocalizationManager.shared.text("sftp_renamed")
                await listCurrent()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func delete(_ items: [SFTPRemoteEntry]) {
        guard !items.isEmpty else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                for item in items {
                    try await deleteRecursive(item)
                }
                statusMessage = LocalizationManager.shared.text("sftp_deleted")
                await listCurrent()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func upload(localURLs: [URL]) {
        let urls = localURLs.filter { !$0.path.isEmpty }
        guard !urls.isEmpty else { return }
        beginTransfer {
            try await self.performUpload(urls, into: self.currentPath)
            await self.listCurrent()
        }
    }

    public func download(_ items: [SFTPRemoteEntry]) {
        guard !items.isEmpty else { return }
        if items.count == 1, !items[0].isDirectory {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = items[0].name
            panel.prompt = LocalizationManager.shared.text("sftp_save")
            guard panel.runModal() == .OK, let dest = panel.url else { return }
            beginTransfer {
                try await self.downloadFile(items[0], to: dest, fileIndex: 1, fileCount: 1)
            }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = LocalizationManager.shared.text("sftp_save")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        beginTransfer {
            var index = 0
            let fileCount = max(items.filter { !$0.isDirectory }.count, items.count)
            for item in items {
                try Task.checkCancellation()
                index += 1
                if item.isDirectory {
                    let dest = folder.appendingPathComponent(item.name, isDirectory: true)
                    try await self.downloadDirectory(item, to: dest, fileIndex: index, fileCount: fileCount)
                } else {
                    try await self.downloadFile(
                        item,
                        to: folder.appendingPathComponent(item.name),
                        fileIndex: index,
                        fileCount: fileCount
                    )
                }
            }
        }
    }

    public func cancelTransfer() {
        transferTask?.cancel()
    }

    public func shutdown() async {
        shuttingDown = true
        keepAliveTask?.cancel()
        keepAliveTask = nil
        transferTask?.cancel()
        transferTask = nil
        transfer = nil
        isAlive = false
        try? await sftp.close()
        try? await ssh.close()
    }

    private func handleDisconnect() {
        guard !shuttingDown else { return }
        isAlive = false
        errorMessage = LocalizationManager.shared.text("sftp_disconnected")
        SessionManager.shared.markSessionDisconnected(id: sessionID)
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: SSHKeepAlive.intervalNanoseconds)
                guard let self, !Task.isCancelled else { return }
                if !self.ssh.isConnected {
                    self.handleDisconnect()
                    return
                }
                if self.isBusy || self.isTransferring { continue }
                do {
                    _ = try await self.sftp.getRealPath(atPath: ".")
                } catch {
                    if !self.ssh.isConnected {
                        self.handleDisconnect()
                        return
                    }
                }
            }
        }
    }

    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }

    private func resolveHomeAndList() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let home = try await sftp.getRealPath(atPath: ".")
            _ = await listAndCommit(home.isEmpty ? "/" : home, recordHistory: false)
        } catch {
            _ = await listAndCommit("/", recordHistory: false)
            if entries.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func listAndCommit(_ path: String, recordHistory: Bool) async -> Bool {
        listGeneration += 1
        let generation = listGeneration
        isBusy = true
        defer {
            if generation == listGeneration {
                isBusy = false
            }
        }
        do {
            let listed = try await fetchEntries(path)
            guard generation == listGeneration else { return false }
            if recordHistory, !currentPath.isEmpty, currentPath != path {
                pathHistory.append(currentPath)
            }
            currentPath = path
            entries = listed
            canGoBack = !pathHistory.isEmpty
            errorMessage = nil
            statusMessage = String(
                format: LocalizationManager.shared.text("sftp_item_count"),
                listed.count
            )
            return true
        } catch {
            guard generation == listGeneration else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func listCurrent() async {
        let path = currentPath.isEmpty ? "/" : currentPath
        _ = await listAndCommit(path, recordHistory: false)
    }

    private func fetchEntries(_ path: String) async throws -> [SFTPRemoteEntry] {
        let names = try await sftp.listDirectory(atPath: path)
        return names.flatMap(\.components)
            .filter { Self.isSafeName($0.filename) }
            .map { component in
                SFTPRemoteEntry(
                    name: component.filename,
                    path: SFTPPath.join(path == "." ? "/" : path, component.filename),
                    kind: SFTPFileType.kind(attributes: component.attributes, longname: component.longname),
                    size: component.attributes.size,
                    modified: component.attributes.accessModificationTime?.modificationTime,
                    permissions: component.attributes.permissions,
                    longname: component.longname
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func beginTransfer(_ work: @escaping @MainActor () async throws -> Void) {
        guard transferTask == nil else {
            errorMessage = LocalizationManager.shared.text("sftp_transfer_busy")
            return
        }
        transferTask = Task { @MainActor in
            do {
                try await work()
                if !Task.isCancelled {
                    statusMessage = LocalizationManager.shared.text("sftp_transfer_done")
                }
            } catch is CancellationError {
                statusMessage = LocalizationManager.shared.text("sftp_transfer_cancelled")
            } catch {
                errorMessage = error.localizedDescription
            }
            transfer = nil
            transferTask = nil
        }
    }

    private func performUpload(_ urls: [URL], into directory: String) async throws {
        let files = try flattenLocal(urls, remoteParent: directory)
        var index = 0
        for item in files {
            try Task.checkCancellation()
            index += 1
            let accessed = item.url.startAccessingSecurityScopedResource()
            defer {
                if accessed { item.url.stopAccessingSecurityScopedResource() }
            }
            if item.isDirectory {
                try await ensureDirectory(item.remotePath)
                continue
            }
            try await uploadFile(
                from: item.url,
                to: item.remotePath,
                fileIndex: index,
                fileCount: files.count
            )
        }
    }

    private struct LocalUploadItem {
        let url: URL
        let remotePath: String
        let isDirectory: Bool
    }

    private func flattenLocal(_ urls: [URL], remoteParent: String) throws -> [LocalUploadItem] {
        var items: [LocalUploadItem] = []
        for url in urls {
            try walkLocal(url, remoteParent: remoteParent, into: &items)
        }
        return items
    }

    private func walkLocal(_ url: URL, remoteParent: String, into items: inout [LocalUploadItem]) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        let remotePath = SFTPPath.join(remoteParent, url.lastPathComponent)
        if isDir.boolValue {
            items.append(LocalUploadItem(url: url, remotePath: remotePath, isDirectory: true))
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children {
                try walkLocal(child, remoteParent: remotePath, into: &items)
            }
        } else {
            items.append(LocalUploadItem(url: url, remotePath: remotePath, isDirectory: false))
        }
    }

    private func ensureDirectory(_ path: String) async throws {
        do {
            try await sftp.createDirectory(atPath: path)
        } catch {
            if let attributes = try? await sftp.getAttributes(at: path),
               SFTPFileType.kind(attributes: attributes, longname: "") == .directory {
                return
            }
            throw error
        }
    }

    private func uploadFile(from url: URL, to remotePath: String, fileIndex: Int, fileCount: Int) async throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let total = Int64(values.fileSize ?? 0)
        transfer = SFTPTransferProgress(
            fileName: url.lastPathComponent,
            direction: .upload,
            completedBytes: 0,
            totalBytes: total,
            fileIndex: fileIndex,
            fileCount: fileCount
        )
        let reader = FileHandleBox(try FileHandle(forReadingFrom: url))
        defer { reader.close() }
        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                guard let chunk = try reader.handle.read(upToCount: sftpChunkSize), !chunk.isEmpty else { break }
                try await file.write(ByteBuffer(data: chunk), at: offset)
                offset += UInt64(chunk.count)
                await MainActor.run {
                    self.transfer?.completedBytes = Int64(offset)
                }
            }
        }
    }

    private func downloadFile(
        _ entry: SFTPRemoteEntry,
        to dest: URL,
        fileIndex: Int,
        fileCount: Int
    ) async throws {
        let temp = dest.appendingPathExtension("aeroterm-partial")
        if FileManager.default.fileExists(atPath: temp.path) {
            try FileManager.default.removeItem(at: temp)
        }
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let writer = FileHandleBox(try FileHandle(forWritingTo: temp))
        do {
            transfer = SFTPTransferProgress(
                fileName: entry.name,
                direction: .download,
                completedBytes: 0,
                totalBytes: Int64(entry.size ?? 0),
                fileIndex: fileIndex,
                fileCount: fileCount
            )

            try await sftp.withFile(filePath: entry.path, flags: .read) { file in
                var offset: UInt64 = 0
                while true {
                    try Task.checkCancellation()
                    var buffer = try await file.read(from: offset, length: UInt32(sftpChunkSize))
                    let count = buffer.readableBytes
                    if count == 0 { break }
                    if let data = buffer.readData(length: count) {
                        try writer.handle.write(contentsOf: data)
                    }
                    offset += UInt64(count)
                    await MainActor.run {
                        self.transfer?.completedBytes = Int64(offset)
                        if let size = entry.size {
                            self.transfer?.totalBytes = Int64(size)
                        }
                    }
                }
            }
            writer.close()
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: temp, to: dest)
        } catch {
            writer.close()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    private func downloadDirectory(
        _ entry: SFTPRemoteEntry,
        to dest: URL,
        fileIndex: Int,
        fileCount: Int
    ) async throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let children = try await fetchEntries(entry.path)
        var index = fileIndex
        for child in children {
            try Task.checkCancellation()
            let childDest = dest.appendingPathComponent(child.name, isDirectory: child.isDirectory)
            if child.isDirectory {
                try await downloadDirectory(child, to: childDest, fileIndex: index, fileCount: fileCount)
            } else {
                try await downloadFile(child, to: childDest, fileIndex: index, fileCount: fileCount)
                index += 1
            }
        }
    }

    private func deleteRecursive(_ entry: SFTPRemoteEntry) async throws {
        if entry.isDirectory {
            let names = try await sftp.listDirectory(atPath: entry.path)
            let children = names.flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }
            for component in children {
                let child = SFTPRemoteEntry(
                    name: component.filename,
                    path: SFTPPath.join(entry.path, component.filename),
                    kind: SFTPFileType.kind(attributes: component.attributes, longname: component.longname),
                    size: component.attributes.size,
                    modified: nil,
                    permissions: component.attributes.permissions,
                    longname: component.longname
                )
                try await deleteRecursive(child)
            }
            try await sftp.rmdir(at: entry.path)
        } else {
            try await sftp.remove(at: entry.path)
        }
    }
}
