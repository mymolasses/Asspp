import SwiftUI

struct AccountView: View {
    @ObservedObject private var vm = AppStore.this
    @State private var addAccount = false
    @State private var transferMode: AccountTransferView.Mode?
    @State private var query = ""
    @State private var navigationPath = NavigationPath()

    private var filteredAccounts: [AppStore.UserAccount] {
        vm.accounts.filter { query.isEmpty || $0.id.localizedStandardContains(query) || $0.regionName.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Manage Apple IDs and encrypted backups.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Label("Apple IDs", systemImage: "lock.shield").font(.headline)
                        Text(vm.accounts.count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Button { addAccount = true } label: { Label("Add Account", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                    }
                    if vm.accounts.isEmpty {
                        UnavailableView(label: { Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark") },
                            description: { Text("Add an Apple ID to start downloading IPA packages.") },
                            actions: { Button("Import Accounts") { transferMode = .importBackup } })
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if filteredAccounts.isEmpty {
                        Text("No Matching Accounts").foregroundStyle(.secondary).padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                            ForEach(filteredAccounts) { account in
                                NavigationLink(value: account.id) { accountCard(account) }.buttonStyle(.plain)
                            }
                        }
                    }
                    Label("Your accounts are saved in your Keychain and will be synced across devices with the same iCloud account signed in.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 1040).padding(24).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color.blue.opacity(0.035))
            .navigationTitle("Accounts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Search Accounts")
            .navigationDestination(for: AppStore.UserAccount.ID.self) { AccountDetailView(accountId: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Import Accounts", systemImage: "square.and.arrow.down") { transferMode = .importBackup }
                        Button("Export Accounts", systemImage: "square.and.arrow.up") { transferMode = .exportBackup }
                            .disabled(vm.accounts.isEmpty)
                    } label: { Label("Account Backup", systemImage: "arrow.up.arrow.down") }
                }
            }
        }
        .sheet(item: $transferMode) { AccountTransferView(mode: $0) }
        .sheet(isPresented: $addAccount) {
            NavigationStack { AddAccountView() }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 380)
                #endif
        }
    }

    private func accountCard(_ account: AppStore.UserAccount) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(.blue)
                Spacer()
                Text(account.regionName).font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.blue.opacity(0.08), in: Capsule())
            }
            Text(account.id).font(.headline).lineLimit(1).truncationMode(.middle)
                .redacted(reason: .placeholder, isEnabled: vm.demoMode)
            AccountSessionLabel(accountID: account.id).font(.caption)
            Divider()
            HStack {
                Text("View Details").font(.subheadline).foregroundStyle(.blue)
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).librarySurface()
    }
}

struct AccountSessionLabel: View {
    let accountID: String
    @ObservedObject private var store = AppStore.this

    var body: some View {
        if store.refreshingAccountIDs.contains(accountID) {
            Label("Refreshing", systemImage: "arrow.clockwise").foregroundStyle(.secondary)
        } else if store.sessionErrors[accountID] != nil {
            Label("Sign In Required", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        } else if store.verifiedAccountIDs.contains(accountID) {
            Label("Verified", systemImage: "checkmark.circle").foregroundStyle(.green)
        } else {
            Label("Not Yet Checked", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}
