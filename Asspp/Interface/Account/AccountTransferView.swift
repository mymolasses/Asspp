import SwiftUI
import UniformTypeIdentifiers

struct AccountTransferView: View {
    enum Mode: String, Identifiable {
        case importBackup, exportBackup
        var id: String { rawValue }
        var title: String {
            switch self {
            case .importBackup: String(localized: "Import Accounts")
            case .exportBackup: String(localized: "Export Accounts")
            }
        }
    }

    let mode: Mode
    var accountIDs: Set<String>? = nil
    @ObservedObject private var store = AppStore.this
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var fileURL: URL?
    @State private var document: AccountBackupDocument?
    @State private var imported: [AppStore.UserAccount] = []
    @State private var busy = false
    @State private var error = ""
    @State private var message = ""

    private var exportedAccounts: [AppStore.UserAccount] {
        store.accounts.filter { accountIDs?.contains($0.id) ?? true }
    }

    private var conflictCount: Int {
        let existing = Set(store.accounts.map { $0.id.lowercased() })
        return imported.count { existing.contains($0.id.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Compatible with AssppWeb encrypted backups", systemImage: "lock.shield")
                    Text("Backups include passwords and login sessions. Keep the file and its password private.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if mode == .importBackup {
                    Section {
                        Button { showImporter = true } label: {
                            Label(fileURL?.lastPathComponent ?? String(localized: "Choose Backup File"), systemImage: "doc.badge.arrow.up")
                                .lineLimit(2)
                        }
                        .disabled(busy)
                    }
                } else {
                    Section {
                        LabeledContent("Accounts", value: "\(exportedAccounts.count)")
                    }
                }
                if imported.isEmpty {
                    Section {
                        SecureField("Backup Password", text: $password)
                        if mode == .exportBackup {
                            SecureField("Confirm Password", text: $confirmation)
                        }
                    }
                    .disabled(busy)
                    Section {
                        Button {
                            Task { await prepare() }
                        } label: {
                            HStack {
                                if busy { ProgressView().controlSize(.small) }
                                Text(mode.title)
                            }
                        }
                        .disabled(busy || password.isEmpty ||
                            (mode == .importBackup ? fileURL == nil : exportedAccounts.isEmpty || password != confirmation))
                    } footer: {
                        if mode == .exportBackup, !confirmation.isEmpty, confirmation != password {
                            Text("Passwords do not match.").foregroundStyle(.red)
                        }
                    }
                } else {
                    Section {
                        LabeledContent("Accounts in Backup", value: "\(imported.count)")
                        LabeledContent("Existing Accounts", value: "\(conflictCount)")
                        Button("Import and Keep Existing Accounts") { finishImport(overwrite: false) }
                        if conflictCount > 0 {
                            Button("Import and Replace Existing Accounts", role: .destructive) { finishImport(overwrite: true) }
                                .disabled(!store.refreshingAccountIDs.isEmpty)
                        }
                    } footer: {
                        Text("Imported sessions are checked the next time you use them. You may need to sign in again.")
                    }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                if !message.isEmpty { Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) } }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(busy)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
        .interactiveDismissDisabled(busy)
        // Unknown .enc extensions are not consistently classified as public.data.
        // Validate the bounded encrypted payload after selection instead.
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                fileURL = urls.first
                imported = []
                error = ""
                message = ""
            case let .failure(failure): error = failure.localizedDescription
            }
        }
        .fileExporter(isPresented: $showExporter, document: document, contentType: .data,
                      defaultFilename: "asspp-accounts.backup.enc") { result in
            document = nil
            switch result {
            case .success:
                message = String(localized: "Account backup exported.")
                password = ""
                confirmation = ""
            case let .failure(failure): error = failure.localizedDescription
            }
        }
    }

    @MainActor
    private func prepare() async {
        busy = true
        error = ""
        message = ""
        defer { busy = false }
        let password = password
        do {
            if mode == .exportBackup {
                let accounts = exportedAccounts.map {
                    AccountTransfer.WebAccount($0, fallbackDeviceIdentifier: store.deviceIdentifier)
                }
                let encrypted = try await Task.detached(priority: .userInitiated) {
                    try AccountTransfer.export(accounts: accounts, password: password)
                }.value
                document = AccountBackupDocument(data: encrypted)
                showExporter = true
            } else if let fileURL {
                imported = try await Task.detached(priority: .userInitiated) {
                    let access = fileURL.startAccessingSecurityScopedResource()
                    defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
                    return try AccountTransfer.decode(AccountBackupCrypto.readFile(fileURL), password: password)
                }.value
                self.password = ""
            }
        } catch { self.error = error.localizedDescription }
    }

    private func finishImport(overwrite: Bool) {
        let count = store.importAccounts(imported, overwrite: overwrite)
        imported = []
        fileURL = nil
        message = String(localized: "Imported \(count) accounts.")
    }
}

private struct AccountBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw AccountBackupCrypto.Failure.invalidBackup }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
