import AppKit
import Combine
import SwiftTerm

@MainActor
public final class AgentCLISession: ObservableObject {
    public let sessionID: UUID
    public let terminalView: LocalProcessTerminalView

    @Published public var isAlive: Bool = true

    private let command: String
    private let arguments: String?
    private let workingDirectory: String?
    private let environmentVariables: [String: String]?
    private var themeSignature = ""
    private var started = false
    private let processDelegate: AgentCLIProcessDelegate

    public init(
        sessionID: UUID,
        command: String,
        arguments: String?,
        workingDirectory: String?,
        environmentVariables: [String: String]?
    ) {
        self.sessionID = sessionID
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        let view = LocalProcessTerminalView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        view.focusRingType = .none
        self.terminalView = view
        let delegate = AgentCLIProcessDelegate(sessionID: sessionID)
        self.processDelegate = delegate
        view.processDelegate = delegate
        applyTheme()
        delegate.onTerminated = { [weak self] in
            self?.isAlive = false
        }
    }

    public func start() {
        guard !started else { return }
        started = true

        let expandedDir: String
        if let dir = workingDirectory, !dir.isEmpty {
            expandedDir = (dir as NSString).expandingTildeInPath
        } else {
            expandedDir = FileManager.default.homeDirectoryForCurrentUser.path
        }

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(currentPath)"
        if let customEnvs = environmentVariables {
            for (key, value) in customEnvs where !value.isEmpty {
                env[key] = value
            }
        }
        let envArray = env.map { "\($0.key)=\($0.value)" }

        var initCommands: [String] = []
        if let customEnvs = environmentVariables {
            for (key, value) in customEnvs where !value.isEmpty {
                initCommands.append("export \(key)=\"\(value)\"")
            }
        }
        if !command.isEmpty, command != "/bin/zsh" {
            if let arguments, !arguments.isEmpty {
                initCommands.append("\(command) \(arguments)")
            } else {
                initCommands.append(command)
            }
        }

        var shellArgs = ["-l"]
        if !initCommands.isEmpty {
            shellArgs = ["-l", "-i", "-c", initCommands.joined(separator: " && ")]
        }

        terminalView.startProcess(
            executable: "/bin/zsh",
            args: shellArgs,
            environment: envArray,
            execName: "/bin/zsh",
            currentDirectory: expandedDir
        )
    }

    public func attach(to container: NSView) {
        if let host = container as? TerminalHostView {
            host.install(terminalView)
        } else {
            TerminalAppearance.paintContainer(container)
            terminalView.pinFilling(container)
        }
        applyTheme()
    }

    public func detach(from container: NSView) {
        if let host = container as? TerminalHostView {
            host.uninstall(terminalView)
            return
        }
        if terminalView.superview === container {
            terminalView.removeFromSuperview()
        }
    }

    public func applyTheme() {
        TerminalAppearance.apply(to: terminalView, lastSignature: &themeSignature)
    }

    public func shutdown() {
        terminalView.terminate()
        isAlive = false
    }
}

private final class AgentCLIProcessDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    let sessionID: UUID
    var onTerminated: (@MainActor () -> Void)?

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let sessionID = self.sessionID
        let callback = onTerminated
        DispatchQueue.main.async {
            callback?()
            SessionManager.shared.markSessionDisconnected(id: sessionID)
        }
    }
}
