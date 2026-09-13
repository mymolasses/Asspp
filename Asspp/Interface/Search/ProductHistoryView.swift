//
//  ProductHistoryView.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import SwiftUI

struct ProductHistoryView: View {
    @StateObject private var vm: AppPackageArchive
    @State private var started = false
    @State private var visibleCount = 50
    @ObservedObject private var store = AppStore.this
    @State private var showAccountDetails = false

    init(accountID: String, region: String, package: AppStore.AppPackage) {
        _vm = StateObject(wrappedValue: AppPackageArchive(accountID: accountID, region: region, package: package))
    }
    @State private var showErrorAlert = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            if let id = vm.accountIdentifier {
                if store.refreshingAccountIDs.contains(id) {
                    Text("登录已失效，正在本地刷新令牌…")
                }
                if let error = store.sessionErrors[id] {
                    Text(error).foregroundStyle(.red)
                    Button("账号详情 / 输入验证码") { showAccountDetails = true }
                }
            }
            if vm.loading {
                HStack {
                    ProgressView()
                    Text("正在请求历史版本，接口较慢时请稍候…")
                }
            }
            if vm.versionIdentifiers.isEmpty, !vm.loading {
                Text(vm.error ?? "暂无历史版本，点击右上角刷新重试。")
            }
            ForEach(Array(vm.versionIdentifiers.prefix(visibleCount)), id: \.self) { key in
                if let aid = vm.accountIdentifier, let pkg = vm.package(for: key) {
                    Menu {
                        Button("Download \(pkg.software.version)") {
                            Task {
                                do {
                                    try await Downloads.this.startDownload(for: pkg, accountID: aid)
                                } catch {
                                    vm.error = error.localizedDescription
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(pkg.software.version)
                                .foregroundStyle(.accent)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                } else {
                    Button {
                        vm.populateVersionItem(for: key)
                    } label: {
                        HStack {
                            Text(key).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            if visibleCount < vm.versionIdentifiers.count {
                Button("显示更多历史版本") { visibleCount += 50 }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Version History")
        .sheet(isPresented: $showAccountDetails) {
            NavigationStack {
                AccountDetailView(accountId: vm.accountIdentifier ?? "")
                    .toolbar { Button("完成") { showAccountDetails = false } }
            }
        }
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Menu {
                    Button {
                        vm.populateNextVersionItems()
                    } label: {
                        Label("Load More", systemImage: "arrow.down.circle")
                    }
                    .disabled(vm.isVersionItemsFullyLoaded)
                    Divider()
                    Button(role: .destructive) {
                        vm.clearVersionItems()
                        vm.populateVersionIdentifiers {
                            await MainActor.run { vm.populateNextVersionItems() }
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(vm.loading) // just make sure
                .opacity(vm.loading ? 0 : 1)
                .overlay { // using overlay to maintain same size while loading
                    if vm.loading {
                        ProgressView()
                            .progressViewStyle(.circular)
                        #if os(macOS)
                            .controlSize(.small)
                        #endif
                    }
                }
            }
        }
        .alert("Oops", isPresented: $showErrorAlert) {
            Button("OK") {
                vm.error = nil
                if vm.shouldDismiss {
                    dismiss()
                }
            }
        } message: {
            Text(vm.error ?? String(localized: "Unknown Error"))
        }
        .onChange(of: vm.error) { newValue in
            showErrorAlert = newValue != nil
        }
        .task {
            guard !started else { return }
            started = true
            logger.info("history: destination rendered")
            // Allow navigation to render before starting the request chain.
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { started = false; return }
            vm.populateVersionIdentifiers {
                await MainActor.run { vm.populateNextVersionItems() }
            }
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .automatic
        #endif
    }
}
