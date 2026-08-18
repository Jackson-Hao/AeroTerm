import SwiftUI
import AppKit

public struct ConnectionEditorView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    @State private var name: String
    @State private var host: String
    @State private var portString: String
    @State private var username: String
    @State private var accountID: UUID?
    @State private var customArgs: String
    @State private var workingDirectory: String
    @State private var envVars: [String: String]
    @State private var selectedBaudRate: Int
    @State private var availablePorts: [SerialPortInfo] = []
    @State private var errorText: String?
    @State private var isShowingAccountEditor = false
    @State private var isShowingAccountManager = false

    private let configID: UUID
    private let type: SessionType

    public init(config: ConnectionConfig) {
        self.configID = config.id
        self.type = config.type
        _name = State(initialValue: config.name)
        _host = State(initialValue: config.host)
        _portString = State(initialValue: "\(config.port)")
        _username = State(initialValue: config.username)
        _accountID = State(initialValue: config.accountID)
        _customArgs = State(initialValue: config.customArgs ?? "")
        _workingDirectory = State(initialValue: config.workingDirectory ?? "")
        _envVars = State(initialValue: config.envVars ?? [:])
        _selectedBaudRate = State(initialValue: config.type == .serial ? config.port : 115200)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(loc.text("connection_name_label")) {
                TextField(loc.text("connection_untitled"), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field(loc.text("connection_type_label")) {
                HStack(spacing: 8) {
                    Image(systemName: type.iconName)
                        .foregroundColor(type.tintColor)
                    Text(type.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
            }

            if type == .agentCLI {
                agentFields
            } else if type == .serial {
                serialFields
            } else {
                networkFields
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(loc.text("connection_save")) { persist() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $isShowingAccountEditor) {
            AccountEditorView(
                account: nil,
                defaultKind: type.accountKind,
                onSave: { account in
                    accountID = account.id
                    isShowingAccountEditor = false
                },
                onCancel: { isShowingAccountEditor = false }
            )
            .padding(22)
            .frame(width: 460)
        }
        .sheet(isPresented: $isShowingAccountManager) {
            AccountManagerSheet()
        }
        .onAppear {
            if type == .serial {
                availablePorts = SerialEngine.getAvailablePorts()
            }
        }
    }

    private var networkFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                field(loc.text("host_label")) {
                    TextField("127.0.0.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                field(loc.text("port_label")) {
                    TextField("22", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                }
            }

            if type.usesAccountPicker {
                remoteAccountPicker
            }
        }
    }

    private var remoteAccountPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.text("account_label"))
                .font(.system(size: 11.5, weight: .semibold))
            HStack(spacing: 8) {
                Picker("", selection: $accountID) {
                    Text(loc.text("account_select_placeholder")).tag(Optional<UUID>.none)
                    ForEach(sessionManager.accounts(for: type)) { account in
                        Text(account.pickerLabel).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                Button(loc.text("account_new")) { isShowingAccountEditor = true }
                Button(loc.text("account_manage")) { isShowingAccountManager = true }
            }
            if let account = sessionManager.account(id: accountID) {
                Text("\(account.kind.displayName)  ·  \(account.username.isEmpty ? "—" : account.username)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var serialFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(loc.text("serial_port_label")) {
                if availablePorts.isEmpty {
                    TextField("/dev/cu.usbserial", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    Picker("", selection: $host) {
                        ForEach(availablePorts, id: \.path) { port in
                            Text("\(port.name) (\(port.path))").tag(port.path)
                        }
                    }
                    .labelsHidden()
                }
            }
            field(loc.text("baud_rate_label")) {
                Picker("", selection: $selectedBaudRate) {
                    ForEach([9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600], id: \.self) { rate in
                        Text("\(rate)").tag(rate)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }

    private var agentFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Binary Command / Executable") {
                TextField("claude", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            field("Startup Arguments") {
                TextField("Optional CLI arguments", text: $customArgs)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            field("Working Directory") {
                HStack {
                    TextField("~", text: $workingDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button(loc.text("browse")) { browseDirectory() }
                }
            }
            if !envVars.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Environment Variables")
                        .font(.system(size: 11.5, weight: .semibold))
                    ForEach(envVars.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 160, alignment: .leading)
                            TextField("Value", text: Binding(
                                get: { envVars[key] ?? "" },
                                set: { envVars[key] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        }
    }

    private func persist() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = loc.text("connection_name_required")
            return
        }
        if type.usesAccountPicker, accountID == nil {
            errorText = loc.text("account_required")
            return
        }

        let account = sessionManager.account(id: accountID)
        var config = ConnectionConfig(
            id: configID,
            name: trimmed,
            type: type,
            host: type == .serial ? host : host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: type == .serial ? selectedBaudRate : (Int(portString) ?? type.defaultPort),
            username: account?.username ?? username,
            authMethod: account?.authMethod ?? .password,
            accountID: accountID,
            customArgs: customArgs.isEmpty ? nil : customArgs,
            workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
            envVars: envVars.isEmpty ? nil : envVars
        )
        if type == .agentCLI {
            config.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            config.port = 0
        }
        sessionManager.saveConnection(config, connectImmediately: false)
        errorText = nil
    }

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
            content()
        }
    }
}
