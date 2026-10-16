//
//  AccountView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI

struct AccountView: View {
    @ObservedObject private var vm = AppStore.this
    @State private var addAccount = false
    @State private var transferMode: AccountTransferView.Mode?
    @State private var query = ""

    private var filteredAccounts: [AppStore.UserAccount] {
        vm.accounts.filter { query.isEmpty || $0.id.localizedStandardContains(query) || $0.regionName.localizedStandardContains(query) }
    }
    @State private var selectedID: AppStore.UserAccount.ID?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        Group {
            #if os(macOS)
                macOSBody
            #else
                iOSBody
            #endif
        }
        .sheet(item: $transferMode) { AccountTransferView(mode: $0) }
    }

    private var transferMenu: some View {
        Menu {
            Button { transferMode = .importBackup } label: { Label("Import Accounts", systemImage: "square.and.arrow.down") }
            Button { transferMode = .exportBackup } label: { Label("Export Accounts", systemImage: "square.and.arrow.up") }
                .disabled(vm.accounts.isEmpty)
        } label: {
            Label("Account Backup", systemImage: "arrow.up.arrow.down")
        }
    }

    #if os(macOS)
        private var macOSBody: some View {
            NavigationStack(path: $navigationPath) {
                accountsTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .navigationTitle("Accounts")
                    .toolbar { macToolbar }
                    .searchable(text: $query, prompt: "Search Accounts")
            }
            .sheet(isPresented: $addAccount) {
                AddAccountView()
                    .frame(minWidth: 480, idealWidth: 520, minHeight: 340, idealHeight: 380)
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }

        private var accountsTable: some View {
            Table(filteredAccounts, selection: $selectedID) {
                TableColumn("Email") { account in
                    Text(account.account.email)
                        .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                TableColumn("Region") { account in
                    Text(account.regionName)
                }
                .width(min: 40, ideal: 60, max: 80)

                TableColumn("Storefront") { account in
                    Text(account.account.store)
                }
                .width(min: 60, ideal: 80, max: 120)

                TableColumn("Session") { account in
                    AccountSessionLabel(accountID: account.id)
                }
                .width(min: 90, ideal: 120)

                TableColumn("") { account in
                    Button {
                        navigationPath.append(account.id)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .width(32)
            }
            .contextMenu(forSelectionType: AppStore.UserAccount.ID.self) { ids in
                if let id = ids.first {
                    Button("View Details") {
                        navigationPath.append(id)
                    }
                }
            }
            .navigationDestination(for: AppStore.UserAccount.ID.self) { id in
                AccountDetailView(accountId: id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if !vm.accounts.isEmpty, filteredAccounts.isEmpty {
                    Text("No Matching Accounts").foregroundStyle(.secondary)
                } else if vm.accounts.isEmpty {
                    UnavailableView(
                        label: {
                            Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                        },
                        description: {
                            Text("Add an Apple ID to start downloading IPA packages.")
                        },
                        actions: {
                            Button("Add Account") { addAccount.toggle() }
                            Button("Import Accounts") { transferMode = .importBackup }
                        },
                    )
                    .padding()
                }
            }
        }

        private var footer: some View {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                Text("Accounts are stored securely in your Keychain and can be removed at any time from the detail view.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        @ToolbarContentBuilder
        private var macToolbar: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) { transferMenu }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addAccount.toggle()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
    #endif

    #if !os(macOS)
        private var iOSBody: some View {
            NavigationStack(path: $navigationPath) {
                Group {
                    if vm.accounts.isEmpty {
                        UnavailableView(
                            label: {
                                Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                            },
                            description: {
                                Text("Add an Apple ID to start downloading IPA packages.")
                            },
                            actions: {
                                Button("Add Account") { addAccount.toggle() }
                                Button("Import Accounts") { transferMode = .importBackup }
                            },
                        )
                    } else {
                        Form {
                            Section {
                                if filteredAccounts.isEmpty { Text("No Matching Accounts").foregroundStyle(.secondary) }
                                ForEach(filteredAccounts) { account in
                                    NavigationLink(value: account.id) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(account.account.email)
                                                    .lineLimit(1).truncationMode(.middle)
                                                    .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                                                AccountSessionLabel(accountID: account.id)
                                                    .font(.caption)
                                            }
                                            Spacer()
                                        }
                                        .badge(account.regionName)
                                    }
                                }
                            } header: {
                                Text("Apple IDs")
                            } footer: {
                                Text("Your accounts are saved in your Keychain and will be synced across devices with the same iCloud account signed in.")
                            }
                        }
                        .formStyle(.grouped)
                    }
                }
                .navigationDestination(for: AppStore.UserAccount.ID.self) { id in
                    AccountDetailView(accountId: id)
                }
                .navigationTitle("Accounts")
                .searchable(text: $query, prompt: "Search Accounts")
                .toolbar {
                    ToolbarItem { transferMenu }
                    ToolbarItem {
                        Button {
                            addAccount.toggle()
                        } label: {
                            Label("Add Account", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $addAccount) {
                NavigationStack {
                    AddAccountView()
                }
            }
        }
    #endif
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
