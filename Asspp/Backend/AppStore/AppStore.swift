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
    @Published var refreshingAccountIDs: Set<String> = []
    @Published var sessionErrors: [String: String] = [:]
    @Published var verifiedAccountIDs: Set<String> = []
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
        sessionErrors.removeValue(forKey: account.id)
        verifiedAccountIDs.insert(account.id)
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
        do {
            return try await performWithAccount(id: id, body)
        } catch ApplePackageError.sessionExpired {
            // Retry only a definite authentication rejection, never a timeout
            // or an ambiguous purchase result. SAP handles login locally.
            _ = try await rotate(id: id)
            return try await performWithAccount(id: id, body)
        }
    }

    private nonisolated func performWithAccount<T>(id: String, _ body: (inout UserAccount) async throws -> T) async throws -> T {
        guard let original = await accounts.first(where: { $0.id == id }) else {
            throw AuthenticationError.accountNotFound
        }
        var account = original
        let result: Result<T, Error>
        do { result = .success(try await body(&account)) }
        catch { result = .failure(error) }
        let updatedAccount = account
        await MainActor.run {
            // A slow request must not overwrite a newer login/session. Compare
            // Apple Account, not UserAccount (whose equality is identity only).
            guard let idx = accounts.firstIndex(where: { $0.id == id }),
                  accounts[idx].account == original.account else { return }
            if updatedAccount.account != original.account {
                accounts[idx] = updatedAccount
            }
            switch result {
            case .success:
                verifiedAccountIDs.insert(id)
                sessionErrors.removeValue(forKey: id)
            case .failure(ApplePackageError.sessionExpired):
                verifiedAccountIDs.remove(id)
                sessionErrors[id] = ApplePackageError.sessionExpired.localizedDescription
            default: break
            }
        }
        return try result.get()
    }
}
