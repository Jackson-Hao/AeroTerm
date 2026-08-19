import Foundation
import Combine
import Darwin

public struct SerialPortInfo: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public final class SerialEngine: ObservableObject, @unchecked Sendable {
    @Published public var availablePorts: [SerialPortInfo] = []
    @Published public var selectedPortPath: String = ""
    @Published public var baudRate: Int = 115200
    @Published public var settings: SerialSettings = .default
    @Published public var isOpened = false
    @Published public var logs: [NetworkLogItem] = []
    @Published public var rxBytes: Int = 0
    @Published public var txBytes: Int = 0
    @Published public var lastErrorMessage: String? = nil
    @Published public var receiveFileURL: URL? = nil
    @Published public var fileTransferLabel: String? = nil

    public var onRawBytes: ((Data) -> Void)?
    public var onDisconnected: ((String) -> Void)?

    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var pathWatchSource: DispatchSourceFileSystemObject?
    private var pathWatchFD: Int32 = -1
    private let queue = DispatchQueue(label: "com.aeroterm.serial.queue", qos: .userInitiated)
    private var isDisposed = false
    private var isHandlingLoss = false
    private let lock = NSLock()
    /// Byte buffer, not `Data` slices — repeated `removeSubrange` leaves a non-zero startIndex and crashes.
    private var pendingRX: [UInt8] = []
    private var pendingFlush: DispatchWorkItem?
    private var pendingLogItems: [NetworkLogItem] = []
    private var logFlushScheduled = false
    private static let maxPendingRX = 65_536
    private static let maxRowBytes = 4_096

    /// IOSSIOSPEED = _IOW('T', 2, speed_t) on Darwin.
    private static let iossIOSpeed: UInt = 0x80085402

    public init() {
        refreshPorts()
    }

    public static func getAvailablePorts() -> [SerialPortInfo] {
        var ports: [SerialPortInfo] = []
        let fileManager = FileManager.default
        if let devFiles = try? fileManager.contentsOfDirectory(atPath: "/dev") {
            for file in devFiles where file.hasPrefix("cu.") {
                let fullPath = "/dev/\(file)"
                let friendlyName = file.replacingOccurrences(of: "cu.", with: "")
                ports.append(SerialPortInfo(path: fullPath, name: friendlyName))
            }
        }
        return ports.sorted { $0.name < $1.name }
    }

    public func refreshPorts() {
        let ports = Self.getAvailablePorts()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.availablePorts = ports
            if !ports.isEmpty && (self.selectedPortPath.isEmpty || !ports.contains(where: { $0.path == self.selectedPortPath })) {
                self.selectedPortPath = ports[0].path
            }
        }
    }

    @discardableResult
    public func openPort(path: String, baud: Int, settings: SerialSettings = .default) -> Bool {
        closePort()

        guard !path.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                let message = LocalizationManager.lookup("serial_path_required")
                self?.lastErrorMessage = message
                self?.appendLog(direction: .error, content: message)
            }
            return false
        }

        let requestedBaud = max(baud, 1)
        self.settings = settings
        self.selectedPortPath = path
        self.baudRate = requestedBaud

        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            let errStr = String(cString: strerror(errno))
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDisposed else { return }
                self.lastErrorMessage = LocalizationManager.format("serial_open_failed_fmt", path, errStr)
                self.appendLog(direction: .error, content: LocalizationManager.format("serial_open_failed_fmt", path, errStr))
            }
            return false
        }

        var tty = termios()
        if tcgetattr(fd, &tty) != 0 {
            close(fd)
            let errStr = String(cString: strerror(errno))
            DispatchQueue.main.async { [weak self] in
                let message = LocalizationManager.format("serial_getattr_failed_fmt", errStr)
                self?.lastErrorMessage = message
                self?.appendLog(direction: .error, content: message)
            }
            return false
        }

        // Darwin tcsetattr only accepts the B* constants (max B230400).
        // Put a legal placeholder speed in termios, then set the real rate with IOSSIOSPEED.
        applyRawMode(&tty)
        applyFrame(&tty, settings: settings, allowHardwareFlow: true)
        cfsetispeed(&tty, Self.termiosPlaceholderSpeed(for: requestedBaud))
        cfsetospeed(&tty, Self.termiosPlaceholderSpeed(for: requestedBaud))

        if tcsetattr(fd, TCSANOW, &tty) != 0 {
            applyFrame(&tty, settings: settings, allowHardwareFlow: false)
            if tcsetattr(fd, TCSANOW, &tty) != 0 {
                applyFrame(&tty, settings: .default, allowHardwareFlow: false)
                cfsetispeed(&tty, speed_t(B115200))
                cfsetospeed(&tty, speed_t(B115200))
                if tcsetattr(fd, TCSANOW, &tty) != 0 {
                    let errStr = String(cString: strerror(errno))
                    close(fd)
                    DispatchQueue.main.async { [weak self] in
                        let message = LocalizationManager.format("serial_setattr_failed_fmt", errStr)
                        self?.lastErrorMessage = message
                        self?.appendLog(direction: .error, content: message)
                    }
                    return false
                }
            }
        }

        var speed = speed_t(requestedBaud)
        if ioctl(fd, Self.iossIOSpeed, &speed) != 0, !Self.darwinTermiosSpeeds.contains(speed_t(requestedBaud)) {
            let errStr = String(cString: strerror(errno))
            close(fd)
            DispatchQueue.main.async { [weak self] in
                let message = LocalizationManager.format("serial_baud_apply_failed_fmt", String(requestedBaud), errStr)
                self?.lastErrorMessage = message
                self?.appendLog(direction: .error, content: message)
            }
            return false
        }

        applyModemLines(fd: fd, dtr: settings.dtr, rts: settings.rts)

        lock.lock()
        self.fileDescriptor = fd
        lock.unlock()

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.lock.lock()
            let currentFD = self.fileDescriptor
            self.lock.unlock()
            guard currentFD >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(currentFD, &buffer, buffer.count)
            if bytesRead > 0 {
                self.ingest(Data(buffer[0..<bytesRead]))
                return
            }
            if bytesRead == 0 {
                self.handleDeviceLost(.hangup)
                return
            }
            let err = errno
            if err == EAGAIN || err == EWOULDBLOCK || err == EINTR { return }
            self.handleDeviceLost(.ioError(err))
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        lock.lock()
        self.readSource = source
        lock.unlock()
        source.resume()
        startPathWatch(path)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.selectedPortPath = path
            self.baudRate = requestedBaud
            self.settings = settings
            self.isOpened = true
            self.lastErrorMessage = nil
            self.appendLog(
                direction: .system,
                content: LocalizationManager.format(
                    "serial_log_opened",
                    path,
                    String(requestedBaud),
                    settings.lineSpec,
                    settings.flowControl.symbol
                )
            )
        }

        return true
    }

    public func closePort() {
        teardown(reportClosed: true)
    }

    private func teardown(reportClosed: Bool) {
        stopPathWatch()

        lock.lock()
        let oldSource = self.readSource
        self.readSource = nil
        let fd = self.fileDescriptor
        self.fileDescriptor = -1
        lock.unlock()

        if let source = oldSource {
            // Close now so a later open() cannot reuse this fd before cancel runs.
            if fd >= 0 {
                close(fd)
            }
            source.setCancelHandler {}
            source.cancel()
        } else if fd >= 0 {
            close(fd)
        }

        queue.async { [weak self] in
            self?.flushPendingRX()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            if self.isOpened {
                self.isOpened = false
                if reportClosed {
                    self.appendLog(direction: .system, content: LocalizationManager.lookup("serial_log_closed"))
                }
            }
        }
    }

    private enum DeviceLoss {
        case hangup
        case removed
        case ioError(Int32)

        var message: String {
            switch self {
            case .hangup:
                return LocalizationManager.lookup("serial_disconnected_eof")
            case .removed:
                return LocalizationManager.lookup("serial_disconnected_removed")
            case .ioError(let code):
                return LocalizationManager.format("serial_disconnected_io", String(cString: strerror(code)))
            }
        }
    }

    private func handleDeviceLost(_ reason: DeviceLoss) {
        lock.lock()
        if isHandlingLoss || fileDescriptor < 0 {
            lock.unlock()
            return
        }
        isHandlingLoss = true
        lock.unlock()

        let message = reason.message
        teardown(reportClosed: false)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.isOpened = false
            self.lastErrorMessage = message
            self.appendLog(direction: .error, content: message)
            self.onDisconnected?(message)
            self.lock.lock()
            self.isHandlingLoss = false
            self.lock.unlock()
        }
    }

    private func startPathWatch(_ path: String) {
        stopPathWatch()
        let watchFD = open(path, O_EVTONLY)
        guard watchFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchFD,
            eventMask: [.delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleDeviceLost(.removed)
        }
        source.setCancelHandler {
            close(watchFD)
        }
        pathWatchFD = watchFD
        pathWatchSource = source
        source.resume()
    }

    private func stopPathWatch() {
        if let source = pathWatchSource {
            pathWatchSource = nil
            pathWatchFD = -1
            source.cancel()
        } else if pathWatchFD >= 0 {
            close(pathWatchFD)
            pathWatchFD = -1
        }
    }

    public func send(data: Data, formatIsHex: Bool = false) {
        lock.lock()
        let fd = self.fileDescriptor
        lock.unlock()

        guard fd >= 0, !isDisposed else { return }

        queue.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            let written: Int = data.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress else { return 0 }
                return write(fd, ptr, data.count)
            }
            if written < 0 {
                let err = errno
                if err != EAGAIN && err != EWOULDBLOCK && err != EINTR {
                    self.handleDeviceLost(.ioError(err))
                    return
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDisposed else { return }
                if written > 0 {
                    self.txBytes += written
                    let str = String(data: data, encoding: .utf8) ?? LocalizationManager.lookup("serial_binary_payload")
                    let hex = HexUtils.dataToHexString(data)
                    self.appendLog(direction: .send, content: str, hex: hex, bytes: written, payload: data)
                } else {
                    self.appendLog(direction: .error, content: LocalizationManager.lookup("serial_write_failed"))
                }
            }
        }
    }

    public func sendText(_ text: String, addNewline: Bool = false) {
        var str = text
        if addNewline { str += "\r\n" }
        if let data = str.data(using: .utf8) {
            send(data: data, formatIsHex: false)
        }
    }

    public func sendHex(_ hex: String) {
        if let data = HexUtils.hexStringToData(hex) {
            send(data: data, formatIsHex: true)
        }
    }

    public func sendFile(_ url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var sent = 0
                while true {
                    let chunk = try handle.read(upToCount: TCPIO.chunkSize) ?? Data()
                    if chunk.isEmpty { break }
                    self.send(data: chunk)
                    sent += chunk.count
                }
                DispatchQueue.main.async { [weak self] in
                    self?.fileTransferLabel = LocalizationManager.format(
                        "serial_log_tx_file",
                        url.lastPathComponent,
                        HexUtils.formatByteCount(sent)
                    )
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.lastErrorMessage = error.localizedDescription
                    self?.appendLog(
                        direction: .error,
                        content: LocalizationManager.format("serial_send_file_failed", error.localizedDescription)
                    )
                }
            }
        }
    }

    public func setReceiveFile(_ url: URL?) {
        receiveFileURL = url
        if url == nil {
            fileTransferLabel = nil
        }
    }

    public func clearLogs() {
        pendingFlush?.cancel()
        pendingFlush = nil
        queue.async { [weak self] in
            self?.pendingRX.removeAll(keepingCapacity: true)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.pendingLogItems.removeAll()
            self.logs.removeAll()
            self.rxBytes = 0
            self.txBytes = 0
            self.fileTransferLabel = nil
        }
    }

    /// Serial-queue ingest. Never mutates `Data` slices on the UI path.
    private func ingest(_ data: Data) {
        if let url = receiveFileURL {
            try? TCPIO.append(data, to: url)
        }
        if let onRawBytes {
            DispatchQueue.main.async {
                onRawBytes(data)
            }
        }
        if settings.mode == .shell {
            DispatchQueue.main.async { [weak self] in
                self?.rxBytes += data.count
            }
            return
        }

        pendingRX.append(contentsOf: data)
        var rows: [Data] = []
        while let range = firstLineBreak(in: pendingRX) {
            rows.append(Data(pendingRX[range.line]))
            pendingRX.removeSubrange(range.consumed)
        }
        if pendingRX.count >= Self.maxPendingRX {
            rows.append(Data(pendingRX.prefix(Self.maxRowBytes)))
            pendingRX.removeFirst(min(pendingRX.count, Self.maxRowBytes))
        }
        scheduleFlush()

        let byteCount = data.count
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.rxBytes += byteCount
            for row in rows {
                self.emitRX(row)
            }
        }
    }

    private func scheduleFlush() {
        pendingFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushPendingRX()
        }
        pendingFlush = work
        queue.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func flushPendingRX() {
        pendingFlush?.cancel()
        pendingFlush = nil
        guard !pendingRX.isEmpty else { return }
        let leftover = Data(pendingRX)
        pendingRX.removeAll(keepingCapacity: true)
        DispatchQueue.main.async { [weak self] in
            self?.emitRX(leftover)
        }
    }

    private func emitRX(_ data: Data) {
        guard !data.isEmpty else { return }
        let hex = HexUtils.dataToHexString(data)
        appendLog(
            direction: .receive,
            content: SerialANSI.visibleText(data) { payload in
                String(data: payload, encoding: .utf8) ?? String(decoding: payload, as: UTF8.self)
            },
            hex: hex,
            bytes: data.count,
            payload: data
        )
    }

    private struct LineRange {
        let line: Range<Int>
        let consumed: Range<Int>
    }

    private func firstLineBreak(in bytes: [UInt8]) -> LineRange? {
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x0A {
                return LineRange(line: 0..<i, consumed: 0..<(i + 1))
            }
            if bytes[i] == 0x0D {
                let consume = (i + 1 < bytes.count && bytes[i + 1] == 0x0A) ? i + 2 : i + 1
                return LineRange(line: 0..<i, consumed: 0..<consume)
            }
            i += 1
        }
        return nil
    }

    private func appendLog(direction: LogDirection, content: String, hex: String? = nil, bytes: Int = 0, payload: Data? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.appendLog(direction: direction, content: content, hex: hex, bytes: bytes, payload: payload)
            }
            return
        }
        guard !isDisposed else { return }
        let item = NetworkLogItem(
            direction: direction,
            content: HexUtils.sanitizedText(content),
            hexRepresentation: hex,
            byteCount: bytes,
            payload: payload
        )
        pendingLogItems.append(item)
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingLogs()
        }
    }

    private func flushPendingLogs() {
        logFlushScheduled = false
        guard !isDisposed, !pendingLogItems.isEmpty else { return }
        logs.append(contentsOf: pendingLogItems)
        pendingLogItems.removeAll(keepingCapacity: true)
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }

    private func applyRawMode(_ tty: inout termios) {
        cfmakeraw(&tty)
        tty.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tty.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        tty.c_cc.16 = 1
        tty.c_cc.17 = 0
    }

    private func applyFrame(_ tty: inout termios, settings: SerialSettings, allowHardwareFlow: Bool) {
        tty.c_cflag &= ~tcflag_t(CSIZE)
        tty.c_cflag |= settings.dataBits.termiosFlag
        applyParity(&tty, settings.parity)
        applyStopBits(&tty, settings.stopBits)
        applyFlowControl(&tty, allowHardwareFlow ? settings.flowControl : .none)
    }

    /// Speeds Darwin `tcsetattr` accepts. Anything else must go through IOSSIOSPEED.
    private static let darwinTermiosSpeeds: [speed_t] = [
        50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800, 2400, 4800,
        7200, 9600, 14400, 19200, 28800, 38400, 57600, 76800, 115200, 230400
    ]

    private static func termiosPlaceholderSpeed(for baud: Int) -> speed_t {
        let target = speed_t(max(baud, 1))
        if darwinTermiosSpeeds.contains(target) {
            return target
        }
        return darwinTermiosSpeeds.min(by: { abs(Int($0) - Int(target)) < abs(Int($1) - Int(target)) }) ?? speed_t(B115200)
    }

    private func applyParity(_ tty: inout termios, _ parity: SerialParity) {
        switch parity {
        case .none:
            tty.c_cflag &= ~tcflag_t(PARENB)
            tty.c_cflag &= ~tcflag_t(PARODD)
        case .even:
            tty.c_cflag |= tcflag_t(PARENB)
            tty.c_cflag &= ~tcflag_t(PARODD)
        case .odd:
            tty.c_cflag |= tcflag_t(PARENB | PARODD)
        case .mark, .space:
            tty.c_cflag |= tcflag_t(PARENB)
            if parity == .mark {
                tty.c_cflag |= tcflag_t(PARODD)
            } else {
                tty.c_cflag &= ~tcflag_t(PARODD)
            }
        }
    }

    private func applyStopBits(_ tty: inout termios, _ stopBits: SerialStopBits) {
        switch stopBits {
        case .one:
            tty.c_cflag &= ~tcflag_t(CSTOPB)
        case .onePointFive, .two:
            tty.c_cflag |= tcflag_t(CSTOPB)
        }
    }

    private func applyFlowControl(_ tty: inout termios, _ flow: SerialFlowControl) {
        tty.c_cflag &= ~tcflag_t(CRTSCTS)
        tty.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        switch flow {
        case .none:
            break
        case .rtscts:
            tty.c_cflag |= tcflag_t(CRTSCTS)
        case .xonxoff:
            tty.c_iflag |= tcflag_t(IXON | IXOFF)
        }
    }

    private func applyModemLines(fd: Int32, dtr: Bool, rts: Bool) {
        var status: Int32 = 0
        guard ioctl(fd, TIOCMGET, &status) == 0 else { return }
        if dtr {
            status |= TIOCM_DTR
        } else {
            status &= ~TIOCM_DTR
        }
        if rts {
            status |= TIOCM_RTS
        } else {
            status &= ~TIOCM_RTS
        }
        _ = ioctl(fd, TIOCMSET, &status)
    }

    deinit {
        isDisposed = true
        closePort()
    }
}

private extension SerialDataBits {
    var termiosFlag: tcflag_t {
        switch self {
        case .five: return tcflag_t(CS5)
        case .six: return tcflag_t(CS6)
        case .seven: return tcflag_t(CS7)
        case .eight: return tcflag_t(CS8)
        }
    }
}
