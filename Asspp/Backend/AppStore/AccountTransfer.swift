import ApplePackage
import Foundation

enum AccountTransfer {
    struct WebAccount: Codable, Sendable {
        var email: String
        var password: String
        var appleId: String
        var store: String
        var firstName: String
        var lastName: String
        var passwordToken: String
        var directoryServicesIdentifier: String
        var cookies: [ApplePackage.Cookie]
        var deviceIdentifier: String
        var pod: String?

        init(_ user: AppStore.UserAccount, fallbackDeviceIdentifier: String) {
            let account = user.account
            email = account.email
            password = account.password
            appleId = account.appleId
            store = account.store
            firstName = account.firstName
            lastName = account.lastName
            passwordToken = account.passwordToken
            directoryServicesIdentifier = account.directoryServicesIdentifier
            cookies = account.cookie
            deviceIdentifier = user.deviceIdentifier ?? fallbackDeviceIdentifier
            pod = account.pod
        }

        func userAccount() throws -> AppStore.UserAccount {
            let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, email.contains("@"), !password.isEmpty,
                  !passwordToken.isEmpty, !directoryServicesIdentifier.isEmpty,
                  ApplePackage.Configuration.countryCode(for: store) != nil,
                  !deviceIdentifier.isEmpty, deviceIdentifier.count <= 128,
                  deviceIdentifier.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
            else { throw AccountBackupCrypto.Failure.invalidBackup }
            let account = ApplePackage.Account(email: email, password: password, appleId: appleId,
                store: store, firstName: firstName, lastName: lastName, passwordToken: passwordToken,
                directoryServicesIdentifier: directoryServicesIdentifier, cookie: cookies, pod: pod)
            return AppStore.UserAccount(account: account, deviceIdentifier: deviceIdentifier)
        }
    }

    private struct Envelope: Codable {
        var format = "asspp.accounts"
        var version = 1
        var accounts: [WebAccount]
    }

    static func export(accounts: [WebAccount], password: String) throws -> Data {
        try AccountBackupCrypto.encrypt(JSONEncoder().encode(Envelope(accounts: accounts)), password: password)
    }

    static func decode(_ data: Data, password: String) throws -> [AppStore.UserAccount] {
        let plaintext = try AccountBackupCrypto.decrypt(data, password: password)
        let decoder = JSONDecoder()
        let webAccounts: [WebAccount]
        if let legacy = try? decoder.decode([WebAccount].self, from: plaintext) {
            webAccounts = legacy
        } else {
            guard let envelope = try? decoder.decode(Envelope.self, from: plaintext),
                  envelope.format == "asspp.accounts", envelope.version == 1 else {
                throw AccountBackupCrypto.Failure.invalidBackup
            }
            webAccounts = envelope.accounts
        }
        guard !webAccounts.isEmpty else { throw AccountBackupCrypto.Failure.invalidBackup }
        // Validate every entry before changing Keychain. Duplicate entries in a
        // single file resolve to the last entry, matching the web account store.
        var byEmail: [String: AppStore.UserAccount] = [:]
        for webAccount in webAccounts {
            let user = try webAccount.userAccount()
            byEmail[user.id.lowercased()] = user
        }
        return byEmail.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}

extension AppStore {
    @discardableResult
    func importAccounts(_ imported: [UserAccount], overwrite: Bool) -> Int {
        var merged = accounts
        var count = 0
        for user in imported {
            if let index = merged.firstIndex(where: { $0.id.lowercased() == user.id.lowercased() }) {
                guard overwrite else { continue }
                let oldID = merged[index].id
                guard !refreshingAccountIDs.contains(oldID) else { continue }
                merged[index] = user
                verifiedAccountIDs.remove(oldID)
                sessionErrors.removeValue(forKey: oldID)
            } else {
                merged.append(user)
            }
            // Imported tokens have not yet been checked against Apple.
            verifiedAccountIDs.remove(user.id)
            sessionErrors.removeValue(forKey: user.id)
            count += 1
        }
        accounts = merged.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        return count
    }
}
