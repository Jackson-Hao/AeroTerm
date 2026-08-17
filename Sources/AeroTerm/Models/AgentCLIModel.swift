import Foundation
import SwiftUI
import AppKit

public struct AgentEnvKey: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var required: Bool
    public var placeholder: String
    public var value: String = ""

    public init(name: String, required: Bool = false, placeholder: String = "", value: String = "") {
        self.name = name
        self.required = required
        self.placeholder = placeholder
        self.value = value
    }
}

public struct AgentCLIConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var command: String
    public var defaultArgs: String
    public var description: String
    public var icon: String
    public var iconFile: String?
    public var tintColorHex: String
    public var envKeys: [AgentEnvKey]
    public var workingDirectory: String = "~"

    public init(
        id: String,
        name: String,
        category: String,
        command: String,
        defaultArgs: String,
        description: String,
        icon: String,
        iconFile: String? = nil,
        tintColorHex: String,
        envKeys: [AgentEnvKey],
        workingDirectory: String = "~"
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.command = command
        self.defaultArgs = defaultArgs
        self.description = description
        self.icon = icon
        self.iconFile = iconFile
        self.tintColorHex = tintColorHex
        self.envKeys = envKeys
        self.workingDirectory = workingDirectory
    }

    public var tintColor: Color {
        Color(hex: tintColorHex)
    }

    @MainActor
    public var localImage: NSImage? {
        guard let file = iconFile, !file.isEmpty else { return nil }
        if let url = Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Icons") {
            return NSImage(contentsOf: url)
        } else if let url = Bundle.main.url(forResource: file, withExtension: nil) {
            return NSImage(contentsOf: url)
        }
        let devPath = "/Users/jackson-hao/code/AeroTerm/Sources/AeroTerm/Resources/Icons/\(file)"
        return NSImage(contentsOfFile: devPath)
    }
}
