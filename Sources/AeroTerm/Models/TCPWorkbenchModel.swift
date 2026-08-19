import Foundation

public enum TCPTextEncoding: String, CaseIterable, Identifiable, Sendable {
    case utf8 = "UTF-8"
    case ascii = "ASCII"
    case gb18030 = "GB18030"
    case gbk = "GBK"
    case latin1 = "ISO-8859-1"
    case utf16le = "UTF-16LE"

    public var id: String { rawValue }

    public func encode(_ text: String) -> Data? {
        switch self {
        case .utf8:
            return text.data(using: .utf8)
        case .ascii:
            return text.data(using: .ascii)
        case .latin1:
            return text.data(using: .isoLatin1)
        case .utf16le:
            return text.data(using: .utf16LittleEndian)
        case .gb18030, .gbk:
            let ns = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return (text as NSString).data(using: ns)
        }
    }

    public func decode(_ data: Data) -> String {
        switch self {
        case .utf8:
            return String(data: data, encoding: .utf8) ?? fallback(data)
        case .ascii:
            return String(data: data, encoding: .ascii) ?? fallback(data)
        case .latin1:
            return String(data: data, encoding: .isoLatin1) ?? fallback(data)
        case .utf16le:
            return String(data: data, encoding: .utf16LittleEndian) ?? fallback(data)
        case .gb18030, .gbk:
            let ns = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return NSString(data: data, encoding: ns).map { $0 as String } ?? fallback(data)
        }
    }

    private var cfEncoding: CFStringEncoding {
        switch self {
        case .gb18030:
            return CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        case .gbk:
            return CFStringEncoding(CFStringEncodings.GBK_95.rawValue)
        default:
            return CFStringBuiltInEncodings.UTF8.rawValue
        }
    }

    private func fallback(_ data: Data) -> String {
        HexUtils.dataToHexString(data)
    }
}

public enum TCPLineEnding: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case lf = "LF"
    case cr = "CR"
    case crlf = "CRLF"

    public var id: String { rawValue }

    public var bytes: Data {
        switch self {
        case .none: return Data()
        case .lf: return Data([0x0A])
        case .cr: return Data([0x0D])
        case .crlf: return Data([0x0D, 0x0A])
        }
    }
}

public enum TCPIO {
    public static let chunkSize = 32_768

    public static func append(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss:SSS"
        return formatter
    }()
}
