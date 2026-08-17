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
    @Published public var isOpened = false
    @Published public var logs: [NetworkLogItem] = []
    @Published public var rxBytes: Int = 0
    @Published public var txBytes: Int = 0
    @Published public var lastErrorMessage: String? = nil

    public static let supportedBaudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]

    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.aeroterm.serial.queue", qos: .userInitiated)
    private var isDisposed = false
    private let lock = NSLock()

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
    public func openPort(path: String, baud: Int) -> Bool {
        closePort()

        guard !path.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.lastErrorMessage = "未指定串口设备路径"
            }
            return false
        }

        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            let errStr = String(cString: strerror(errno))
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDisposed else { return }
                self.lastErrorMessage = "无法打开串口 (\(path)): \(errStr)"
                self.appendLog(direction: .error, content: "无法打开串口 \(path): \(errStr)")
            }
            return false
        }

        var tty = termios()
        if tcgetattr(fd, &tty) != 0 {
            close(fd)
            let errStr = String(cString: strerror(errno))
            DispatchQueue.main.async { [weak self] in
                self?.lastErrorMessage = "获取串口属性失败: \(errStr)"
            }
            return false
        }

        cfmakeraw(&tty)
        let speed = speed_t(baud)
        cfsetspeed(&tty, speed)

        tty.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tty.c_cflag &= ~tcflag_t(CSIZE)
        tty.c_cflag |= tcflag_t(CS8)
        tty.c_cflag &= ~tcflag_t(PARENB)
        tty.c_cflag &= ~tcflag_t(CSTOPB)
        tty.c_cflag &= ~tcflag_t(CRTSCTS)

        if tcsetattr(fd, TCSANOW, &tty) != 0 {
            close(fd)
            let errStr = String(cString: strerror(errno))
            DispatchQueue.main.async { [weak self] in
                self?.lastErrorMessage = "配置串口波特率与参数失败: \(errStr)"
            }
            return false
        }

        lock.lock()
        self.fileDescriptor = fd
        self.selectedPortPath = path
        self.baudRate = baud

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isDisposed else { return }
                    self.rxBytes += data.count
                    let str = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    let hex = HexUtils.dataToHexString(data)
                    self.appendLog(direction: .receive, content: str, hex: hex, bytes: data.count)
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.readSource = source
        source.resume()
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            self.isOpened = true
            self.lastErrorMessage = nil
            self.appendLog(direction: .system, content: "串口已打开: \(path) @ \(baud) bps (8-N-1)")
        }

        return true
    }

    public func closePort() {
        lock.lock()
        let oldSource = self.readSource
        self.readSource = nil
        let fd = self.fileDescriptor
        self.fileDescriptor = -1
        lock.unlock()

        if let source = oldSource {
            source.cancel()
        } else if fd >= 0 {
            close(fd)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            if self.isOpened {
                self.isOpened = false
                self.appendLog(direction: .system, content: "串口已关闭")
            }
        }
    }

    public func send(data: Data, formatIsHex: Bool = false) {
        lock.lock()
        let fd = self.fileDescriptor
        let opened = self.isOpened
        lock.unlock()

        guard opened, fd >= 0, !isDisposed else { return }

        queue.async { [weak self] in
            guard let self = self, !self.isDisposed else { return }
            data.withUnsafeBytes { rawBuffer in
                if let ptr = rawBuffer.baseAddress {
                    let written = write(fd, ptr, data.count)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, !self.isDisposed else { return }
                        if written > 0 {
                            self.txBytes += written
                            let str = String(data: data, encoding: .utf8) ?? "<二进制数据>"
                            let hex = HexUtils.dataToHexString(data)
                            self.appendLog(direction: .send, content: str, hex: hex, bytes: written)
                        }
                    }
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

    public func clearLogs() {
        logs.removeAll()
        rxBytes = 0
        txBytes = 0
    }

    private func appendLog(direction: LogDirection, content: String, hex: String? = nil, bytes: Int = 0) {
        guard !isDisposed else { return }
        let item = NetworkLogItem(
            direction: direction,
            content: content,
            hexRepresentation: hex,
            byteCount: bytes
        )
        self.logs.append(item)
        if self.logs.count > 1000 {
            self.logs.removeFirst(self.logs.count - 1000)
        }
    }

    deinit {
        isDisposed = true
        closePort()
    }
}
