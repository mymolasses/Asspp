//
//  ProductView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import ButtonKit
import Kingfisher
import SwiftUI

struct ProductView: View {
    @StateObject private var archive: AppPackageArchive
    @Binding var navigationPath: NavigationPath

    var region: String {
        archive.region
    }

    init(archive: AppStore.AppPackage, region: String, navigationPath: Binding<NavigationPath>) {
        _archive = StateObject(wrappedValue: AppPackageArchive(accountID: nil, region: region, package: archive))
        _navigationPath = navigationPath
    }

    @ObservedObject private var vm = AppStore.this
    @ObservedObject private var dvm = Downloads.this

    var eligibleAccounts: [AppStore.UserAccount] {
        vm.accounts
    }

    var account: AppStore.UserAccount? {
        vm.accounts.first { $0.id == selection }
    }

    @State private var selection: AppStore.UserAccount.ID = .init()
    @State private var licenseHint: Hint?
    @State private var showLicenseAlert = false
    @State private var hint: Hint?
    @State private var isAcquiringLicense = false
    @State private var showPurchaseResult = false
    @State private var showAccountDetails = false

    let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    var formattedSize: String? {
        guard let sizeBytes = archive.package.software.fileSizeBytes.flatMap(Int64.init(_:)) else {
            return nil
        }
        return sizeFormatter.string(fromByteCount: sizeBytes)
    }

    var body: some View {
        Form {
            accountSelector
            buttons
            packageHeader
            packageDetails
            packageDescription
            if account == nil {
                Section {
                    Text("No account available for this region.")
                        .foregroundStyle(.red)
                } header: {
                    Text("Error")
                } footer: {
                    Text("Please add an account in the Accounts page.")
                }
            }
            pricing
        }
        .formStyle(.grouped)
        .onAppear {
            if account == nil {
                selection = vm.eligibleAccounts(for: region).first?.id ?? eligibleAccounts.first?.id ?? .init()
            }
        }
        .sheet(isPresented: $showAccountDetails) {
            NavigationStack {
                AccountDetailView(accountId: selection)
                    .toolbar { Button("完成") { showAccountDetails = false } }
            }
        }
        .navigationTitle("Select Account")
        .alert("购买请求结果", isPresented: $showPurchaseResult) {
            Button("确定", role: .cancel) {}
            if vm.sessionErrors[selection] != nil {
                Button("打开账号 / 输入验证码") { showAccountDetails = true }
            }
        } message: {
            Text(licenseHint?.message ?? "")
        }
        .alert("License Required", isPresented: $showLicenseAlert) {
            var confirmRole: ButtonRole?
            #if compiler(>=6.2)
                if #available(iOS 26.0, macOS 26.0, *) {
                    confirmRole = .confirm
                }
            #endif

            return Group {
                Button("Acquire License", role: confirmRole) {
                    Task {
                        await requestLicense()
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        } message: {}
    }

    /// AppStore retries an explicitly expired session once using local SAP.
    private func acquireLicense() async throws {
        guard let account else { return }
        try await vm.withAccount(id: account.id) { userAccount in
            try await ApplePackage.Purchase.purchase(
                account: &userAccount.account,
                app: archive.package.software,
            )
        }
        licenseHint = Hint(message: String(localized: "Request Succeeded"), color: .green)
    }

    private func requestLicense() async {
        guard !isAcquiringLicense, account != nil else { return }
        isAcquiringLicense = true
        defer { isAcquiringLicense = false }
        do { try await acquireLicense() }
        catch { licenseHint = Hint(message: error.localizedDescription, color: .red) }
        showPurchaseResult = true
    }

    var packageHeader: some View {
        Section {
            PackageDisplayView(archive: archive.package)
            Button {
                logger.info("history: navigation requested")
                navigationPath.append(HistoryDestination(accountID: selection, region: region, package: archive.package))
            } label: {
                let badgeText = archive.releaseDate.flatMap { date in
                    Text(date.formatted(.relative(presentation: .numeric)))
                }

                Text("Version \(archive.package.software.version)")
                    .badge(badgeText)
            }
            .disabled(account == nil)
        } header: {
            Text("Package")
        }
    }

    var packageDetails: some View {
        Section {
            CopyableRow(label: "Bundle ID", value: archive.package.software.bundleID, monospaced: true)
            Text("Developer")
                .badge(archive.package.software.sellerName)
            if !archive.package.software.primaryGenreName.isEmpty {
                Text("Category")
                    .badge(archive.package.software.primaryGenreName)
            }
            if let formattedSize {
                Text("Size")
                    .badge(formattedSize)
            }
            Text("Compatibility")
                .badge("\(archive.package.software.minimumOsVersion)+")
            if archive.package.software.userRatingCount > 0 {
                Text("Rating")
                    .badge("\(String(format: "%.1f", archive.package.software.averageUserRating)) (\(archive.package.software.userRatingCount))")
            }
        } header: {
            Text("Details")
        }
    }

    var packageDescription: some View {
        Section {
            Text(archive.package.software.releaseNotes ?? "")
        } header: {
            Text("What's New")
        }
    }

    var pricing: some View {
        Section {
            Text("\(archive.formattedPrice ?? "N/A")")
            if archive.price == 0 {
                Button {
                    Task { await requestLicense() }
                } label: {
                    HStack {
                        if isAcquiringLicense { ProgressView() }
                        Text(isAcquiringLicense ? "正在请求购买…" : "请求购买 / 获取许可证")
                    }
                }
                .disabled(account == nil || isAcquiringLicense)
            }
        } header: {
            Text("Pricing")
        } footer: {
            if let licenseHint {
                Text(licenseHint.message)
                    .foregroundStyle(licenseHint.color ?? .primary)
            } else {
                Text("Acquiring a license is not available for paid apps. Purchase from the App Store first, then download here. If you've already purchased it, this may fail.")
            }
        }
    }

    var accountSelector: some View {
        Section {
            Menu {
                ForEach(eligibleAccounts) { account in
                    Button("\(account.account.email) · \(account.regionName)") {
                        selection = account.id
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(account?.account.email ?? "请选择账号")
                            .lineLimit(1).truncationMode(.middle)
                        Text(account?.regionName ?? "未知地区")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                }
            }
            .redacted(reason: .placeholder, isEnabled: vm.demoMode)
            if vm.refreshingAccountIDs.contains(selection) {
                HStack { ProgressView(); Text("登录失效，正在本地刷新令牌…") }
            } else if let error = vm.sessionErrors[selection] {
                Text(error).foregroundStyle(.red)
            } else if account != nil, !vm.verifiedAccountIDs.contains(selection) {
                Text("已载入保存的登录信息，尚未验证；请求时若已失效，将自动刷新一次。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("账号详情 / 刷新令牌 / 验证码") { showAccountDetails = true }
                .disabled(account == nil)
        } header: {
            Text("Account")
        } footer: {
            Text("搜索地区：\(AppStore.UserAccount.regionName(for: region))")
        }
    }

    var buttons: some View {
        Section {
            if let req = dvm.downloadRequest(forArchive: archive.package) {
                NavigationLink(value: req) {
                    Text("Show Download")
                }
            } else {
                AsyncButton {
                    guard let account else { return }
                    do {
                        try await dvm.startDownload(for: archive.package, accountID: account.id)
                        hint = Hint(message: String(localized: "Download Requested"), color: nil)
                        if let req = dvm.downloadRequest(forArchive: archive.package) {
                            navigationPath.append(req)
                        }
                    } catch {
                        if case ApplePackageError.licenseRequired = error, archive.package.software.price == 0 {
                            showLicenseAlert = true
                        } else {
                            hint = Hint(message: String(localized: "Unable to retrieve download URL. Please try again later.") + "\n" + error.localizedDescription, color: .red)
                        }
                        throw error
                    }
                } label: {
                    Text("Request Download")
                }
                .disabledWhenLoading()
                .disabled(account == nil)
            }
        } header: {
            Text("Download")
        } footer: {
            if let hint {
                Text(hint.message)
                    .foregroundStyle(hint.color ?? .primary)
            } else {
                Text("Package can be installed later in download page.")
            }
        }
    }
}

extension AppStore.AppPackage {
    var displaySupportedDevicesIcon: String {
        // TODO: assuming iPhone for now
        "iphone"
    }
}
