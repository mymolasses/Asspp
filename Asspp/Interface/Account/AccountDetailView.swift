//
//  AccountDetailView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import ButtonKit
import SwiftUI

struct AccountDetailView: View {
    let accountId: AppStore.UserAccount.ID

    @ObservedObject private var vm = AppStore.this
    @Environment(\.dismiss) var dismiss

    private var account: AppStore.UserAccount? {
        vm.accounts.first { $0.id == accountId }
    }

    @State private var rotatingHint = ""
    @State private var verificationCode = ""
    @State private var needsVerificationCode = false
    @State private var isReauthenticating = false

    var body: some View {
        Form {
            Section {
                Button { copyToClipboard(account?.account.email) } label: {
                    Text(account?.account.email ?? "")
                }
                .foregroundStyle(.primary)
                .redacted(reason: .placeholder, isEnabled: vm.demoMode)
            } header: {
                Text("Apple ID")
            } footer: {
                Text("This email is used to sign in to Apple services.")
            }
            Section {
                Button { copyToClipboard(account?.account.store) } label: {
                    Text(account?.regionName ?? "未知地区")
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Country Code")
            } footer: {
                Text("App Store requires this country code to identify your package region.")
            }
            Section {
                Button { copyToClipboard(account?.account.directoryServicesIdentifier) } label: {
                    Text(account?.account.directoryServicesIdentifier ?? "")
                        .font(.system(.body, design: .monospaced))
                }
                .foregroundStyle(.primary)
                .redacted(reason: .placeholder, isEnabled: vm.demoMode)
            } header: {
                Text("Directory Services ID")
            } footer: {
                Text("This ID, combined with a random seed generated on this device, can be used to download packages from the App Store.")
            }
            Section {
                SecureField(text: .constant(account?.account.passwordToken ?? "")) {
                    Text("Password Token")
                }
                if needsVerificationCode {
                    TextField("2FA Code", text: $verificationCode)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        #endif
                }
                AsyncButton {
                    isReauthenticating = true
                    rotatingHint = "正在重新登录，请稍候…"
                    defer { isReauthenticating = false }
                    do {
                        try await vm.rotate(id: accountId, code: verificationCode)
                        rotatingHint = String(localized: "Success")
                        verificationCode = ""
                        needsVerificationCode = false
                    } catch {
                        rotatingHint = error.localizedDescription
                        needsVerificationCode = error.requiresVerificationCode
                        throw error
                    }
                } label: {
                    HStack {
                        if isReauthenticating { ProgressView() }
                        Text(isReauthenticating ? "正在重新登录…" : "重新登录 / 刷新令牌")
                    }
                }
                .disabledWhenLoading()
                .disabled(vm.refreshingAccountIDs.contains(accountId))
            } header: {
                Text("Password Token")
            } footer: {
                if rotatingHint.isEmpty, let error = vm.sessionErrors[accountId] {
                    Text(error).foregroundStyle(.red)
                } else if rotatingHint.isEmpty {
                    Text("If you fail to acquire a license for a product, rotating the password token may help. This will use the initial password to authenticate with the App Store again.")
                } else {
                    Text(rotatingHint)
                        .foregroundStyle(isReauthenticating ? Color.secondary : Color.primary)
                }
            }
            Section {
                Button("Delete") {
                    vm.delete(id: account?.id ?? "")
                    dismiss()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account Details")
        .onAppear {
            // A failed automatic refresh may already have requested a 2FA code.
            needsVerificationCode = false
        }
    }
}

private extension Error {
    var requiresVerificationCode: Bool {
        guard let appleError = self as? ApplePackageError else {
            return false
        }
        switch appleError {
        case ApplePackageError.verificationCodeRequired, ApplePackageError.invalidVerificationCode:
            true
        default:
            false
        }
    }
}
