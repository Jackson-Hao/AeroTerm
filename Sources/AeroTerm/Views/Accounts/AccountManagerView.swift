import SwiftUI
import AppKit

public struct AccountManagerView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @State private var selectedID: UUID?
    @State private var editorToken = UUID()

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            HSplitView {
                accountList
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
                    .frame(height: geo.size.height)

                Group {
                    if let selectedID, let account = sessionManager.account(id: selectedID) {
                        ScrollView {
                            AccountEditorView(
                                account: account,
                                showsChrome: false
                            )
                            .padding(20)
                        }
                        .id(editorToken)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary.opacity(0.45))
                            Text(loc.text("account_empty"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360)
                .frame(height: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedID == nil {
                selectedID = sessionManager.accounts.first?.id
            }
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.text("account_manager_title"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    createAccount()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(loc.text("account_new"))

                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)
                .help(loc.text("account_delete"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if sessionManager.accounts.isEmpty {
                VStack {
                    Spacer()
                    Text(loc.text("account_empty"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(sessionManager.accounts) { account in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.system(size: 12, weight: .medium))
                            Text("\(account.kind.displayName)  ·  \(account.username.isEmpty ? "—" : account.username)")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                        .tag(Optional(account.id))
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.sidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: selectedID) { _, _ in
                    editorToken = UUID()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func createAccount() {
        let account = AuthAccount(
            name: loc.text("account_untitled"),
            username: ""
        )
        sessionManager.upsertAccount(account)
        selectedID = account.id
        editorToken = UUID()
    }

    private func deleteSelected() {
        guard let selectedID else { return }
        sessionManager.deleteAccount(id: selectedID)
        self.selectedID = sessionManager.accounts.first?.id
        editorToken = UUID()
    }
}

public struct AccountManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var loc = LocalizationManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            AccountManagerView()
            Divider()
            HStack {
                Spacer()
                Button(loc.text("close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 720, height: 460)
    }
}
