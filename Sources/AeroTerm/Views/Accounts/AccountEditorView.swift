import SwiftUI
import AppKit

public struct AccountEditorView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    @State private var accountID: UUID
    @State private var name: String
    @State private var username: String
    @State private var kind: AccountKind
    @State private var authMethod: SSHAuthMethod
    @State private var password: String
    @State private var privateKeyPath: String
    @State private var keyPassphrase: String
    @State private var errorText: String?

    private let isNew: Bool
    private let showsChrome: Bool
    private let onSave: ((AuthAccount) -> Void)?
    private let onCancel: (() -> Void)?

    public init(
        account: AuthAccount?,
        defaultKind: AccountKind = .ssh,
        showsChrome: Bool = true,
        onSave: ((AuthAccount) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        let source = account ?? AuthAccount(name: "", username: "", kind: defaultKind)
        self.isNew = account == nil
        self.showsChrome = showsChrome
        self.onSave = onSave
        self.onCancel = onCancel
        _accountID = State(initialValue: source.id)
        _name = State(initialValue: source.name)
        _username = State(initialValue: source.username)
        _kind = State(initialValue: source.kind)
        _authMethod = State(initialValue: source.kind.usesPrivateKey ? source.authMethod : .password)
        _password = State(initialValue: "")
        _privateKeyPath = State(initialValue: source.privateKeyPath)
        _keyPassphrase = State(initialValue: "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsChrome {
                Text(isNew ? loc.text("account_editor_title_new") : loc.text("account_editor_title_edit"))
                    .font(.system(size: 15, weight: .semibold))
            }

            field(loc.text("account_name_label")) {
                TextField(loc.text("account_name_placeholder"), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Picker(loc.text("account_kind_label"), selection: $kind) {
                ForEach(AccountKind.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .onChange(of: kind) { _, newKind in
                if !newKind.usesPrivateKey {
                    authMethod = .password
                }
            }

            if kind.requiresUsername {
                field(loc.text("account_username_label")) {
                    TextField(loc.text("ssh_username_placeholder"), text: $username)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if kind.usesPrivateKey {
                Picker(loc.text("ssh_auth_method"), selection: $authMethod) {
                    Text(loc.text("ssh_auth_password")).tag(SSHAuthMethod.password)
                    Text(loc.text("ssh_auth_key")).tag(SSHAuthMethod.publicKey)
                }
                .pickerStyle(.segmented)
            }

            if authMethod == .password || !kind.usesPrivateKey {
                field(loc.text("password_label")) {
                    PlainSecureField(
                        isNew ? loc.text("ssh_password_placeholder") : loc.text("account_password_keep"),
                        text: $password
                    )
                    .frame(height: 22)
                }
            } else {
                field(loc.text("ssh_private_key")) {
                    HStack {
                        TextField("~/.ssh/id_ed25519", text: $privateKeyPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button(loc.text("browse")) { browsePrivateKey() }
                    }
                }
                field(loc.text("ssh_key_passphrase")) {
                    PlainSecureField(loc.text("ssh_key_passphrase_placeholder"), text: $keyPassphrase)
                        .frame(height: 22)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            if showsChrome {
                HStack {
                    Spacer()
                    if let onCancel {
                        Button(loc.text("cancel"), action: onCancel)
                    }
                    Button(loc.text("account_save")) { persist() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack {
                    Spacer()
                    Button(loc.text("account_save")) { persist() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func persist() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorText = loc.text("account_name_required")
            return
        }
        if kind.requiresUsername, trimmedUser.isEmpty {
            errorText = loc.text("ssh_username_required")
            return
        }

        let method = kind.usesPrivateKey ? authMethod : .password
        if method == .password {
            if kind.requiresSecret {
                let existing = SecretStore.shared.get(.password, accountID: accountID)
                if password.isEmpty && (isNew || existing == nil) {
                    errorText = loc.text("ssh_credentials_required")
                    return
                }
            }
        } else if privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let existing = SecretStore.shared.get(.privateKey, accountID: accountID)
            if isNew || existing == nil {
                errorText = loc.text("ssh_credentials_required")
                return
            }
        }

        let account = AuthAccount(
            id: accountID,
            name: trimmedName,
            username: kind.requiresUsername ? trimmedUser : trimmedUser,
            kind: kind,
            authMethod: method,
            privateKeyPath: kind.usesPrivateKey ? privateKeyPath : ""
        )
        sessionManager.upsertAccount(account)
        writeSecrets(for: account)
        errorText = nil
        onSave?(account)
    }

    private func writeSecrets(for account: AuthAccount) {
        if account.authMethod == .password {
            if !password.isEmpty {
                SecretStore.shared.set(.password, accountID: account.id, plaintext: password)
            }
            SecretStore.shared.delete(.privateKey, accountID: account.id)
            SecretStore.shared.delete(.keyPassphrase, accountID: account.id)
        } else {
            let expanded = (privateKeyPath as NSString).expandingTildeInPath
            if !expanded.isEmpty, let pem = try? String(contentsOfFile: expanded, encoding: .utf8), !pem.isEmpty {
                SecretStore.shared.set(.privateKey, accountID: account.id, plaintext: pem)
            }
            if !keyPassphrase.isEmpty {
                SecretStore.shared.set(.keyPassphrase, accountID: account.id, plaintext: keyPassphrase)
            }
            SecretStore.shared.delete(.password, accountID: account.id)
        }
    }

    private func browsePrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
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
