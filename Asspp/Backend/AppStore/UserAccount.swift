//
//  UserAccount.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Foundation

extension AppStore {
    struct UserAccount: Codable, Identifiable, Hashable, Equatable, Sendable {
        var id: String {
            account.email
        }

        var account: ApplePackage.Account

        var regionName: String {
            Self.regionName(for: ApplePackage.Configuration.countryCode(for: account.store) ?? account.store)
        }

        static func regionName(for code: String) -> String {
            Locale(identifier: "zh_Hans").localizedString(forRegionCode: code.uppercased()) ?? code
        }

        init(account: ApplePackage.Account) {
            self.account = account
        }

        static func == (lhs: UserAccount, rhs: UserAccount) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}
