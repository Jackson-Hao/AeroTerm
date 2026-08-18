import SwiftUI
import AppKit
import SwiftTerm

/// 通用开源终端容器视图 (基于 SwiftTerm 顶尖开源后端)
/// 支持进程退出检测 (exit / Ctrl+D 自动关闭页面)
public struct SwiftTermContainerView: NSViewRepresentable {
    let command: String?
    let arguments: [String]?
    let workingDirectory: String?
    let environmentVariables: [String: String]?
    let onProcessTerminated: (@Sendable () -> Void)?
    
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared

    public init(
        command: String? = nil,
        arguments: [String]? = nil,
        workingDirectory: String? = nil,
        environmentVariables: [String: String]? = nil,
        onProcessTerminated: (@Sendable () -> Void)? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.onProcessTerminated = onProcessTerminated
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onProcessTerminated: onProcessTerminated)
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.focusRingType = .none
        terminalView.processDelegate = context.coordinator
        
        applyTheme(to: terminalView, lastSignature: &context.coordinator.themeSignature)
        
        // 准备工作目录
        let expandedDir: String
        if let dir = workingDirectory, !dir.isEmpty {
            expandedDir = (dir as NSString).expandingTildeInPath
        } else {
            expandedDir = FileManager.default.homeDirectoryForCurrentUser.path
        }

        // 构造环境变量字典，并补齐 macOS 常用开发 PATH
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = "en_US.UTF-8"
        
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:~/.cargo/bin:~/.nvm/versions/node/$(ls ~/.nvm/versions/node 2>/dev/null | tail -n 1)/bin:\(currentPath)"

        if let customEnvs = environmentVariables {
            for (k, v) in customEnvs where !v.isEmpty {
                env[k] = v
            }
        }
        
        let envArray: [String] = env.map { "\($0.key)=\($0.value)" }

        let shell = "/bin/zsh"
        
        var initCommands: [String] = []
        initCommands.append("cd \"\(expandedDir)\"")

        if let customEnvs = environmentVariables {
            for (k, v) in customEnvs where !v.isEmpty {
                initCommands.append("export \(k)=\"\(v)\"")
            }
        }

        if let cmd = command, !cmd.isEmpty, cmd != "/bin/zsh" {
            let fullCommand: String
            if let extraArgs = arguments, !extraArgs.isEmpty {
                fullCommand = "\(cmd) \(extraArgs.joined(separator: " "))"
            } else {
                fullCommand = cmd
            }
            initCommands.append(fullCommand)
        }

        var shellArgs: [String] = ["-l"]
        if !initCommands.isEmpty {
            let combined = initCommands.joined(separator: " && ")
            shellArgs = ["-l", "-i", "-c", combined]
        }

        // 切换当前进程工作目录并启动 SwiftTerm 内核 PTY 进程
        FileManager.default.changeCurrentDirectoryPath(expandedDir)
        terminalView.startProcess(executable: shell, args: shellArgs, environment: envArray, execName: shell)
        
        return terminalView
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyTheme(to: nsView, lastSignature: &context.coordinator.themeSignature)
        context.coordinator.onProcessTerminated = onProcessTerminated
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: LocalProcessTerminalView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? max(nsView.bounds.width, 1),
            height: proposal.height ?? max(nsView.bounds.height, 1)
        )
    }

    private func applyTheme(to terminalView: LocalProcessTerminalView, lastSignature: inout String) {
        TerminalAppearance.apply(to: terminalView, lastSignature: &lastSignature)
    }

    public final class Coordinator: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
        var onProcessTerminated: (@Sendable () -> Void)?
        var themeSignature = ""

        init(onProcessTerminated: (@Sendable () -> Void)?) {
            self.onProcessTerminated = onProcessTerminated
        }

        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        public func processTerminated(source: TerminalView, exitCode: Int32?) {
            let callback = onProcessTerminated
            DispatchQueue.main.async {
                callback?()
            }
        }
    }
}
