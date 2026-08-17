import Foundation

public struct HexUtils {
    /// Convert Data to Hex string with spacing (e.g. "48 65 6C 6C 6F")
    public static func dataToHexString(_ data: Data, spacing: Bool = true) -> String {
        let separator = spacing ? " " : ""
        return data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    /// Convert Hex string (e.g. "48 65 6c 6c 6f" or "48656c6c6f") to Data
    public static func hexStringToData(_ hex: String) -> Data? {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
        
        guard cleaned.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        return data
    }

    /// Format byte size into human readable string (e.g. 1.2 KB, 3.4 MB)
    public static func formatByteCount(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(count))
    }
}
