import Foundation

public enum ConnectionLogKind: Sendable {
    case info
    case success
    case warning
    case error
}

public struct ConnectionLogLine: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let text: String
    public let kind: ConnectionLogKind

    public init(text: String, kind: ConnectionLogKind) {
        self.id = UUID()
        self.time = Date()
        self.text = text
        self.kind = kind
    }
}

public final class ConnectionHUDState: ObservableObject {
    public let title: String
    public let subtitle: String
    @Published public var lines: [ConnectionLogLine] = []
    @Published public var isFinished: Bool = false
    @Published public var didSucceed: Bool = false
    @Published public var isCancelled: Bool = false

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    @MainActor
    public func log(_ text: String, kind: ConnectionLogKind = .info) {
        lines.append(ConnectionLogLine(text: text, kind: kind))
    }
}
