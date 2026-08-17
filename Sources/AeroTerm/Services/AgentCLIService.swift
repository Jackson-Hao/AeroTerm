import Foundation
import Combine

@MainActor
public final class AgentCLIService: ObservableObject {
    public static let shared = AgentCLIService()

    @Published public var availableAgents: [AgentCLIConfig] = []

    private init() {
        loadConfigsFromXML()
    }

    public func loadConfigsFromXML() {
        var xmlData: Data? = nil

        if let url = Bundle.module.url(forResource: "agent_cli_configs", withExtension: "xml") {
            xmlData = try? Data(contentsOf: url)
        } else if let url = Bundle.main.url(forResource: "agent_cli_configs", withExtension: "xml") {
            xmlData = try? Data(contentsOf: url)
        } else {
            let devPath = "/Users/jackson-hao/code/AeroTerm/Sources/AeroTerm/Resources/agent_cli_configs.xml"
            if FileManager.default.fileExists(atPath: devPath) {
                xmlData = try? Data(contentsOf: URL(fileURLWithPath: devPath))
            }
        }

        guard let data = xmlData else {
            loadFallbackDefaults()
            return
        }

        let helper = XMLParserHelper()
        let parsed = helper.parse(data: data)
        if parsed.isEmpty {
            loadFallbackDefaults()
        } else {
            self.availableAgents = parsed
        }
    }

    private func loadFallbackDefaults() {
        self.availableAgents = [
            AgentCLIConfig(
                id: "claude-code",
                name: "Claude Code CLI",
                category: "AI Coding Assistant",
                command: "claude",
                defaultArgs: "--dangerously-skip-permissions",
                description: "Anthropic's official agentic command-line interface for autonomous coding.",
                icon: "sparkles",
                iconFile: "claude.png",
                tintColorHex: "#D97706",
                envKeys: [
                    AgentEnvKey(name: "ANTHROPIC_API_KEY", required: false, placeholder: "sk-ant-api03-...")
                ]
            ),
            AgentCLIConfig(
                id: "codex-cli",
                name: "Codex CLI",
                category: "OpenAI Agent",
                command: "codex",
                defaultArgs: "",
                description: "OpenAI's advanced code reasoning and autonomous command-line developer environment.",
                icon: "cpu.fill",
                iconFile: "codex.png",
                tintColorHex: "#10B981",
                envKeys: [
                    AgentEnvKey(name: "OPENAI_API_KEY", required: false, placeholder: "sk-proj-...")
                ]
            ),
            AgentCLIConfig(
                id: "antigravity-cli",
                name: "Antigravity CLI",
                category: "Advanced Agentic Coding",
                command: "agy",
                defaultArgs: "",
                description: "Google DeepMind's Advanced Agentic Coding CLI with concurrent subagent dispatch.",
                icon: "brain.head.profile",
                iconFile: "antigravity.png",
                tintColorHex: "#38BDF8",
                envKeys: [
                    AgentEnvKey(name: "GEMINI_API_KEY", required: false, placeholder: "AIzaSy...")
                ]
            ),
            AgentCLIConfig(
                id: "grok-cli",
                name: "Grok CLI",
                category: "xAI Assistant",
                command: "grok",
                defaultArgs: "",
                description: "xAI's real-time reasoning and unfiltered command-line intelligence agent.",
                icon: "bolt.fill",
                iconFile: "grok.png",
                tintColorHex: "#64748B",
                envKeys: [
                    AgentEnvKey(name: "XAI_API_KEY", required: false, placeholder: "xai-...")
                ]
            ),
            AgentCLIConfig(
                id: "hermes-cli",
                name: "Hermes CLI",
                category: "Nous Research",
                command: "hermes",
                defaultArgs: "",
                description: "Nous Research's state-of-the-art open-weights reasoning agent.",
                icon: "flame.fill",
                iconFile: "hermes.png",
                tintColorHex: "#EC4899",
                envKeys: [
                    AgentEnvKey(name: "HERMES_API_KEY", required: false, placeholder: "hermes-...")
                ]
            ),
            AgentCLIConfig(
                id: "custom-agent-cli",
                name: "Custom Agent CLI",
                category: "Custom Shell Tool",
                command: "/bin/zsh",
                defaultArgs: "-l",
                description: "Launch any custom AI agent binary, Python automation script or bespoke LLM terminal tool.",
                icon: "terminal.fill",
                iconFile: "custom.png",
                tintColorHex: "#6366F1",
                envKeys: [
                    AgentEnvKey(name: "CUSTOM_AGENT_ENV", required: false, placeholder: "value")
                ]
            )
        ]
    }
}

// 独立的 XMLParser 解析辅助类 (提取 icon_file)
private final class XMLParserHelper: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var result: [AgentCLIConfig] = []
    private var currentElement = ""
    private var currentID = ""
    private var currentName = ""
    private var currentCategory = ""
    private var currentCommand = ""
    private var currentDefaultArgs = ""
    private var currentDescription = ""
    private var currentIcon = "sparkles"
    private var currentIconFile: String? = nil
    private var currentTintColor = "#9333EA"
    private var currentEnvKeys: [AgentEnvKey] = []

    func parse(data: Data) -> [AgentCLIConfig] {
        result.removeAll()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName

        if elementName == "agent" {
            currentID = attributeDict["id"] ?? UUID().uuidString
            currentName = ""
            currentCategory = ""
            currentCommand = ""
            currentDefaultArgs = ""
            currentDescription = ""
            currentIcon = "sparkles"
            currentIconFile = nil
            currentTintColor = "#9333EA"
            currentEnvKeys = []
        } else if elementName == "env" {
            let name = attributeDict["name"] ?? ""
            let required = (attributeDict["required"] ?? "false").lowercased() == "true"
            let placeholder = attributeDict["placeholder"] ?? ""
            currentEnvKeys.append(AgentEnvKey(name: name, required: required, placeholder: placeholder))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch currentElement {
        case "name":
            currentName += trimmed
        case "category":
            currentCategory += trimmed
        case "command":
            currentCommand += trimmed
        case "default_args":
            currentDefaultArgs += trimmed
        case "description":
            currentDescription += trimmed
        case "icon":
            currentIcon += trimmed
        case "icon_file":
            if currentIconFile == nil {
                currentIconFile = trimmed
            } else {
                currentIconFile? += trimmed
            }
        case "tint_color":
            currentTintColor += trimmed
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "agent" {
            let config = AgentCLIConfig(
                id: currentID,
                name: currentName.isEmpty ? "Agent CLI" : currentName,
                category: currentCategory.isEmpty ? "AI Assistant" : currentCategory,
                command: currentCommand.isEmpty ? "claude" : currentCommand,
                defaultArgs: currentDefaultArgs,
                description: currentDescription,
                icon: currentIcon.isEmpty ? "sparkles" : currentIcon,
                iconFile: currentIconFile,
                tintColorHex: currentTintColor.isEmpty ? "#9333EA" : currentTintColor,
                envKeys: currentEnvKeys
            )
            result.append(config)
        }
    }
}
