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
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ID: \(key)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let metadata = vm.versionItems[key] {
                            Text(metadata.displayVersion)
                                .font(.headline)
                            Text(metadata.releaseDate, format: .dateTime.year().month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if vm.loadingVersionIDs.contains(key) {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(Text("Loading Details..."))
                        } else {
                            if let error = vm.versionErrors[key] {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            Button("View Details") {
                                vm.populateVersionItem(for: key)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Spacer(minLength: 0)
                    if let aid = vm.accountIdentifier, let pkg = vm.package(for: key) {
                        Button("Download") {
                            Task {
                                do {
                                    try await Downloads.this.startDownload(for: pkg, accountID: aid)
                                } catch {
                                    vm.error = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
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
                Button {
                    visibleCount = 50
                    vm.populateVersionIdentifiers()
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .accessibilityLabel(Text("Refresh"))
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
            vm.populateVersionIdentifiers()
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
