import SwiftUI
import AppKit

public struct NewConnectionWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var agentService = AgentCLIService.shared

    @State private var currentStep: Int = 1
    @State private var selectedCategory: SessionCategory = .remote
    @State private var selectedType: SessionType = .ssh
    @State private var selectedAgentCLI: AgentCLIConfig? = nil

    // Step 2 Form States
    @State private var connectionName = ""
    @State private var host = "127.0.0.1"
    @State private var portString = "22"
    @State private var localPortString = "0"
    @State private var udpMode: UDPMode = .unicast
    @State private var httpLabel = ""
    @State private var username = ""
    @State private var password = ""
    @State private var selectedAccountID: UUID?
    @State private var saveToFavorites = true
    @State private var isShowingCancelAlert = false
    @State private var isConnecting = false
    @State private var isShowingAccountEditor = false
    @State private var isShowingAccountManager = false

    // Serial Specific
    @State private var selectedSerialPort = ""
    @State private var selectedBaudRate = 115200
    @State private var serialSettings = SerialSettings.wizardDefault
    @State private var desktopSettings = DesktopDisplaySettings.default
    @State private var availablePorts: [SerialPortInfo] = []

    // Agent CLI Specific
    @State private var agentCommand = "claude"
    @State private var agentArgs = ""
    @State private var agentWorkDir = "~"
    @State private var agentEnvValues: [String: String] = [:]

    // Hover States
    @State private var hoveredType: SessionType? = nil
    @State private var hoveredCategory: SessionCategory? = nil
    @State private var hoveredAgentID: String? = nil

    public init() {}

    public var body: some View {
        ZStack {
            AppBackdrop(material: .sidebar)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                wizardHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
                    .background(Color.primary.opacity(0.035))

                Divider().opacity(0.35)

                Group {
                    if currentStep == 1 {
                        step1ProtocolSelection
                    } else {
                        step2ConfigurationForm
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().opacity(0.35)

                wizardFooter
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.03))
            }
        }
        .frame(minWidth: 840, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .windowToolbar)
        .alert(loc.text("confirm_exit_wizard"), isPresented: $isShowingCancelAlert) {
            Button(loc.text("discard_and_exit"), role: .destructive) {
                sessionManager.closeWizard(enterWorkbench: false)
                dismiss()
            }
            Button(loc.text("keep_editing"), role: .cancel) {}
        } message: {
            Text(loc.text("unsaved_wizard_msg"))
        }
        .onAppear {
            if agentService.availableAgents.isEmpty {
                agentService.loadConfigsFromXML()
            }
        }
    }

    // MARK: - 顶部步骤指示器
    private var wizardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.text("wizard_title"))
                    .font(.system(size: 16, weight: .bold))
                Text(currentStep == 1 ? loc.text("step_1_subtitle") : "\(loc.text("step_2_subtitle")) - \(selectedType == .agentCLI ? (selectedAgentCLI?.name ?? "Agent CLI") : selectedType.rawValue)")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                stepBadge(num: 1, title: loc.text("step_1_title"), isActive: currentStep == 1, isCompleted: currentStep > 1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
                stepBadge(num: 2, title: loc.text("step_2_title"), isActive: currentStep == 2, isCompleted: false)
            }
        }
    }

    private func stepBadge(num: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : (isCompleted ? Color.green : Color.secondary.opacity(0.2)))
                    .frame(width: 20, height: 20)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(num)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isActive ? .white : .secondary)
                }
            }

            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }

    // MARK: - Step 1: 左右两栏分类选择
    private var step1ProtocolSelection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CATEGORIES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                ForEach(SessionCategory.allCases) { category in
                    categoryNavRow(category: category)
                }

                Spacer()
            }
            .frame(width: 240)
            .background {
                ZStack {
                    AppBackdrop(material: .sidebar)
                    Color.primary.opacity(0.025)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if selectedCategory == .agentCLI {
                        ForEach(agentService.availableAgents) { agent in
                            agentCLICardRow(agent: agent)
                        }
                    } else {
                        ForEach(selectedCategory.types) { type in
                            protocolCardRow(type: type)
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func categoryNavRow(category: SessionCategory) -> some View {
        let isSelected = selectedCategory == category
        let isHovered = hoveredCategory == category

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
                if category == .agentCLI {
                    selectedType = .agentCLI
                    if let first = agentService.availableAgents.first {
                        selectAgent(first)
                    }
                } else if let first = category.types.first {
                    selectedType = first
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: category.iconName)
                    .font(.system(size: 13.5))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)

                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCategory = hovering ? category : nil
        }
        .padding(.horizontal, 8)
    }

    private func protocolCardRow(type: SessionType) -> some View {
        let isSelected = selectedType == type
        let isHovered = hoveredType == type

        return Button {
            selectedType = type
            goToStep2()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(type.tintColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: type.iconName)
                        .font(.system(size: 22))
                        .foregroundColor(type.tintColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(type.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        if type.defaultPort > 0 {
                            Text("Port \(type.defaultPort)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }

                    Text(type.description)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected || isHovered ? .accentColor : .secondary.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.12)), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredType = hovering ? type : nil
        }
    }

    private func agentCLICardRow(agent: AgentCLIConfig) -> some View {
        let isSelected = selectedAgentCLI?.id == agent.id
        let isHovered = hoveredAgentID == agent.id

        return Button {
            selectAgent(agent)
            goToStep2()
        } label: {
            HStack(spacing: 16) {
                AgentIconView(
                    iconFile: agent.iconFile,
                    fallbackSymbol: agent.icon,
                    tintColor: agent.tintColor,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(agent.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(agent.command)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Text(agent.description)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected || isHovered ? .accentColor : .secondary.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.12)), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredAgentID = hovering ? agent.id : nil
        }
    }

    private func selectAgent(_ agent: AgentCLIConfig) {
        selectedAgentCLI = agent
        selectedType = .agentCLI
        connectionName = agent.name
        agentCommand = agent.command
        agentArgs = agent.defaultArgs
        agentWorkDir = "~"
        agentEnvValues = [:]
        for env in agent.envKeys {
            agentEnvValues[env.name] = ""
        }
    }

    private func goToStep2() {
        if selectedType == .agentCLI {
            if connectionName.isEmpty, let agent = selectedAgentCLI {
                connectionName = agent.name
            }
        } else if selectedType == .httpClient {
            if connectionName.isEmpty {
                connectionName = selectedType.rawValue
            }
        } else if selectedType == .serial {
            availablePorts = SerialEngine.getAvailablePorts()
            if selectedSerialPort.isEmpty, let first = availablePorts.first {
                selectedSerialPort = first.path
            }
            let short = selectedSerialPort.replacingOccurrences(of: "/dev/cu.", with: "")
            connectionName = short.isEmpty ? "Serial" : "Serial - \(short)"
        } else {
            portString = "\(selectedType.defaultPort)"
            if selectedType == .udpTool {
                localPortString = portString
                applyUDPHostPlaceholder(udpMode)
            }
            if selectedType == .httpServer {
                localPortString = "\(selectedType.defaultPort)"
                host = "0.0.0.0"
            }
            connectionName = "\(selectedType.rawValue) - \(host)"
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = 2
        }
    }

    // MARK: - Step 2: 参数配置表单
    private var step2ConfigurationForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text("connection_name_label"))
                        .font(.system(size: 12, weight: .semibold))
                    TextField("My Connection", text: $connectionName)
                        .textFieldStyle(.roundedBorder)
                }

                if selectedType == .agentCLI {
                    agentCLIFormSection
                } else if selectedType == .serial {
                    serialFormSection
                } else if selectedType == .httpClient {
                    httpClientFormSection
                } else {
                    networkFormSection
                }

                Divider()

                Toggle(loc.text("save_to_saved_connections"), isOn: $saveToFavorites)
                    .font(.system(size: 12))
                if selectedType != .httpClient {
                    Text(loc.text("verify_then_save_hint"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $isShowingAccountEditor) {
            AccountEditorView(
                account: nil,
                defaultKind: selectedType.accountKind,
                onSave: { account in
                    selectedAccountID = account.id
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
    }

    private var agentCLIFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Binary Command / Executable")
                    .font(.system(size: 12, weight: .semibold))
                TextField("Command", text: $agentCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Startup Arguments")
                    .font(.system(size: 12, weight: .semibold))
                TextField("Optional CLI arguments", text: $agentArgs)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Working Directory")
                    .font(.system(size: 12, weight: .semibold))
                HStack {
                    TextField("Working Directory Path", text: $agentWorkDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseDirectory()
                    }
                }
            }

            if let agent = selectedAgentCLI, !agent.envKeys.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Environment Variables (Configured from XML)")
                        .font(.system(size: 12, weight: .semibold))

                    ForEach(agent.envKeys) { env in
                        HStack {
                            Text(env.name)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 180, alignment: .leading)
                            TextField(env.placeholder.isEmpty ? "Value" : env.placeholder, text: Binding(
                                get: { agentEnvValues[env.name] ?? "" },
                                set: { agentEnvValues[env.name] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }
        }
    }

    private var httpClientFormSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.text("group_label"))
                .font(.system(size: 12, weight: .semibold))
            TextField(loc.text("http_label_placeholder"), text: $httpLabel)
                .textFieldStyle(.roundedBorder)
            Text(loc.text("http_label_hint"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var networkFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text("host_label"))
                        .font(.system(size: 12, weight: .semibold))
                    TextField("127.0.0.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text("port_label"))
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Port", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                if selectedType == .tcpClient || selectedType == .udpTool || selectedType == .httpServer {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.text("tcp_local_port"))
                            .font(.system(size: 12, weight: .semibold))
                        TextField(loc.text("tcp_local_port_placeholder"), text: $localPortString)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }
            }

            if selectedType == .udpTool {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text("udp_mode"))
                        .font(.system(size: 12, weight: .semibold))
                    Picker("", selection: $udpMode) {
                        ForEach(UDPMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: udpMode) { _, newMode in
                        applyUDPHostPlaceholder(newMode)
                    }
                }
            }

            if selectedType.usesAccountPicker {
                remoteAccountPicker
            }

            if selectedType == .vnc || selectedType == .rdp {
                DesktopDisplaySettingsForm(settings: $desktopSettings)
            }
        }
    }

    private var remoteAccountPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.text("account_label"))
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                Picker("", selection: $selectedAccountID) {
                    Text(loc.text("account_select_placeholder")).tag(Optional<UUID>.none)
                    ForEach(sessionManager.accounts(for: selectedType)) { account in
                        Text(account.pickerLabel).tag(Optional(account.id))
                    }
                }
                .labelsHidden()

                Button(loc.text("account_new")) {
                    isShowingAccountEditor = true
                }
                Button(loc.text("account_manage")) {
                    isShowingAccountManager = true
                }
            }

            if let account = sessionManager.account(id: selectedAccountID) {
                Text("\(account.kind.displayName)  ·  \(account.username.isEmpty ? "—" : account.username)  ·  \(account.methodLabel)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text(loc.text("account_picker_hint"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            syncAccountSelection()
        }
        .onChange(of: selectedType) { _, _ in
            syncAccountSelection()
        }
    }

    private func syncAccountSelection() {
        let matched = sessionManager.accounts(for: selectedType)
        if let selectedAccountID, matched.contains(where: { $0.id == selectedAccountID }) {
            return
        }
        selectedAccountID = matched.first?.id
    }

    private var serialFormSection: some View {
        SerialSettingsForm(
            devicePath: $selectedSerialPort,
            baudRate: $selectedBaudRate,
            settings: $serialSettings,
            availablePorts: availablePorts,
            onRefresh: {
                availablePorts = SerialEngine.getAvailablePorts()
                if selectedSerialPort.isEmpty, let first = availablePorts.first {
                    selectedSerialPort = first.path
                }
            }
        )
    }

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            agentWorkDir = url.path
        }
    }

    // MARK: - 底部操作栏
    private var wizardFooter: some View {
        HStack {
            Button(role: .destructive) {
                isShowingCancelAlert = true
            } label: {
                Text(loc.text("cancel"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Spacer()

            if currentStep > 1 {
                Button(loc.text("back")) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)
            }

            Button(currentStep == 1 ? loc.text("next") : (isConnecting ? loc.text("ssh_probing") : loc.text("connect_btn"))) {
                if currentStep == 1 {
                    goToStep2()
                } else {
                    Task { await handleConnect() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isConnecting)
        }
    }

    private func handleConnect() async {
        let launchedFromSplash = sessionManager.isShowingStartupSplash
        let portInt = Int(portString) ?? selectedType.defaultPort

        if selectedType == .httpClient {
            let name = connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
            let config = ConnectionConfig(
                name: name.isEmpty ? selectedType.rawValue : name,
                type: .httpClient,
                host: "",
                port: 0,
                label: httpLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let opened = sessionManager.openFromConfig(config)
            guard opened else { return }
            if saveToFavorites {
                sessionManager.saveConnection(config, connectImmediately: false)
            }
            finishConnect(launchedFromSplash: launchedFromSplash)
            return
        }

        if selectedType == .agentCLI {
            let displayTitle = connectionName.isEmpty ? (selectedAgentCLI?.name ?? "Agent CLI") : connectionName
            sessionManager.openAgentCLI(
                title: displayTitle,
                command: agentCommand,
                arguments: agentArgs,
                workingDirectory: agentWorkDir,
                environment: agentEnvValues
            )
            if saveToFavorites {
                let config = ConnectionConfig(
                    name: displayTitle,
                    type: .agentCLI,
                    host: agentCommand,
                    port: 0,
                    username: "",
                    customArgs: agentArgs,
                    workingDirectory: agentWorkDir,
                    envVars: agentEnvValues
                )
                sessionManager.saveConnection(config, connectImmediately: false)
            }
            finishConnect(launchedFromSplash: launchedFromSplash)
            return
        }

        if selectedType.usesAccountAuth {
            guard let accountID = selectedAccountID,
                  let account = sessionManager.account(id: accountID) else {
                sessionManager.alertMessage = loc.text("account_required")
                return
            }
            let config = ConnectionConfig(
                name: connectionName.isEmpty ? "\(selectedType.rawValue) - \(account.username)@\(host)" : connectionName,
                type: selectedType,
                host: host,
                port: portInt,
                username: account.username,
                authMethod: account.authMethod,
                accountID: account.id,
                desktop: (selectedType == .vnc || selectedType == .rdp) ? desktopSettings : .default
            )
            sessionManager.beginRemoteConnect(config, saveOnSuccess: saveToFavorites)
            return
        }

        let serialName: String
        if selectedType == .serial {
            let short = selectedSerialPort.replacingOccurrences(of: "/dev/cu.", with: "")
            serialName = short.isEmpty ? "Serial" : "Serial - \(short)"
        } else {
            serialName = "\(selectedType.rawValue) - \(host)"
        }
        let config = ConnectionConfig(
            name: connectionName.isEmpty ? serialName : connectionName,
            type: selectedType,
            host: selectedType == .serial ? selectedSerialPort : host,
            port: selectedType == .serial ? selectedBaudRate : portInt,
            localPort: (selectedType == .tcpClient || selectedType == .udpTool || selectedType == .httpServer)
                ? (Int(localPortString) ?? selectedType.defaultPort)
                : 0,
            udpMode: selectedType == .udpTool ? udpMode : .unicast,
            username: username,
            serial: selectedType == .serial ? serialSettings : .default
        )

        let opened = sessionManager.openFromConfig(config)
        guard opened else { return }
        if saveToFavorites {
            sessionManager.saveConnection(config, connectImmediately: false)
        }
        finishConnect(launchedFromSplash: launchedFromSplash)
    }

    private func applyUDPHostPlaceholder(_ mode: UDPMode) {
        switch mode {
        case .unicast:
            if host == "239.255.0.1" || host == "255.255.255.255" {
                host = "127.0.0.1"
            }
        case .multicast:
            host = "239.255.0.1"
        case .broadcast:
            host = "255.255.255.255"
        }
    }

    private func finishConnect(launchedFromSplash: Bool) {
        sessionManager.enterWorkbench()
        if !launchedFromSplash {
            dismiss()
        }
    }
}
