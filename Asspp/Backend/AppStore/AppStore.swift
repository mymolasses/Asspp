//
//  AppStore.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Combine
import Foundation

@MainActor
class AppStore: ObservableObject {
    private var _accounts = Persist<[UserAccount]>(
        key: "Accounts",
        defaultValue: [],
        engine: KeychainStorage(service: "wiki.qaq.Asspp.Accounts"),
    )

    var accounts: [UserAccount] {
        get {
            return _accounts.wrappedValue
        }
        set {
            objectWillChange.send()
            _accounts.wrappedValue = newValue
        }
    }

    private var _deviceIdentifier = Persist<String>(
        key: "DeviceIdentifier",
        defaultValue: "",
        engine: KeychainStorage(service: "wiki.qaq.Asspp.DeviceIdentifier"),
    )

    var deviceIdentifier: String {
        get {
            return _deviceIdentifier.wrappedValue
        }
        set {
            objectWillChange.send()
            _deviceIdentifier.wrappedValue = newValue
            ApplePackage.Configuration.deviceIdentifier = newValue
        }
    }

    private var _demoMode = Persist<Bool>(key: "DemoMode", defaultValue: false)

    var demoMode: Bool {
        get {
            return _demoMode.wrappedValue
        }
        set {
            objectWillChange.send()
            _demoMode.wrappedValue = newValue
        }
    }

    static let this = AppStore()

    private init() {
        if deviceIdentifier.isEmpty {
            do {
                let systemIdentifier = try ApplePackage.DeviceIdentifier.system()
                deviceIdentifier = systemIdentifier
                logger.info("obtained system device identifier")
            } catch {
                logger.warning("failed to get system device identifier, falling back to random one: \(error)")
                let randomIdentifier = ApplePackage.DeviceIdentifier.random()
                deviceIdentifier = randomIdentifier
            }
        }
        logger.info("using device identifier: \(deviceIdentifier)")
        ApplePackage.Configuration.deviceIdentifier = deviceIdentifier
    }

    @discardableResult
    func save(email: String, account: ApplePackage.Account) -> UserAccount {
        logger.info("saving account for user")
        let account = UserAccount(account: account)
        accounts = (accounts.filter { $0.account.email != email } + [account])
            .sorted { $0.account.email < $1.account.email }
        return account
    }

    func delete(id: UserAccount.ID) {
        logger.info("deleting account id: \(id)")
        accounts = accounts.filter { $0.id != id }
    }

    var possibleRegions: Set<String> {
        Set(accounts.compactMap { ApplePackage.Configuration.countryCode(for: $0.account.store) })
    }

    func eligibleAccounts(for region: String) -> [UserAccount] {
        accounts.filter { ApplePackage.Configuration.countryCode(for: $0.account.store) == region }
    }

    nonisolated func withAccount<T>(id: String, _ body: (inout UserAccount) async throws -> T) async throws -> T {
        guard var account = await accounts.first(where: { $0.id == id }) else {
            throw AuthenticationError.accountNotFound
        }
        let result = try await body(&account)
        let updatedAccount = account
        // Re-resolve by id: the accounts array may have been mutated (added,
        // removed, re-sorted) during the await, so the original index is stale.
        await MainActor.run {
            if let idx = accounts.firstIndex(where: { $0.id == id }) {
                accounts[idx] = updatedAccount
            }
        }
        return result
    }
}
