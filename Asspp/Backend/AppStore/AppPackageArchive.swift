//
//  AppPackageArchive.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import Combine
import Foundation
import OrderedCollections

@MainActor
class AppPackageArchive: ObservableObject {
    let accountIdentifier: String?
    let region: String

    @Published var package: AppStore.AppPackage

    typealias VersionIdentifier = String
    // History is a disposable server result. Keep it in memory for the lifetime
    // of this screen: navigation must not synchronously decode/encode disk caches.
    // Old cache files are left untouched, but are no longer read on this path.
    @Published var versionIdentifiers: [VersionIdentifier] = []
    @Published var versionItems: OrderedDictionary<VersionIdentifier, VersionMetadata> = [:]

    var isVersionItemsFullyLoaded: Bool {
        return versionIdentifiers.allSatisfy { versionItems[$0] != nil }
    }

    @Published var error: String?
    @Published var loading = false
    @Published var shouldDismiss = false
    private var attemptedVersionIDs: Set<String> = []

    init(accountID: String?, region: String, package: AppStore.AppPackage) {
        accountIdentifier = accountID
        self.region = region
        self.package = package

    }

    func package(for externalVersion: String) -> AppStore.AppPackage? {
        if let metadata = versionItems[externalVersion] {
            var pkg = package
            pkg.software.version = metadata.displayVersion
            pkg.externalVersionID = externalVersion
            return pkg
        } else {
            return nil
        }
    }

    func clearVersionItems() {
        assert(!loading)
        error = nil
        versionIdentifiers = []
        versionItems = [:]
        attemptedVersionIDs = []
    }

    func populateVersionIdentifiers(_ completion: (() async -> Void)? = nil) {
        guard let accountIdentifier, !loading else { return }
        let bundleID = package.software.bundleID
        let software = package.software
        loading = true
        error = nil

        Task {
            do {
                let versions = try await AppStore.this.withAccount(id: accountIdentifier) { userAccount in
                    try await VersionFinder.list(account: &userAccount.account, bundleIdentifier: bundleID, software: software)
                }
                var seen = Set<String>()
                self.versionIdentifiers = versions.reversed().filter { seen.insert($0).inserted }
                var retained: OrderedDictionary<VersionIdentifier, VersionMetadata> = [:]
                for id in self.versionIdentifiers {
                    if let metadata = self.versionItems[id] { retained[id] = metadata }
                }
                self.versionItems = retained
                self.attemptedVersionIDs = []
            } catch {
                logger.warning("history: list request failed: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
            self.loading = false
            await completion?()
        }
    }

    func populateNextVersionItems(count: Int = 3) {
        guard let accountIdentifier, !loading, !isVersionItemsFullyLoaded else { return }
        loading = true
        error = nil

        Task {
                let missing = self.versionIdentifiers.filter { self.versionItems[$0] == nil }
                let unattempted = missing.filter { !self.attemptedVersionIDs.contains($0) }
                let pending = (unattempted.isEmpty ? missing : unattempted).prefix(max(0, count))
                var failures: [String] = []
                for version in pending {
                    self.attemptedVersionIDs.insert(version)
                    let app = self.package.software
                    do {
                        let metadata = try await AppStore.this.withAccount(id: accountIdentifier) { userAccount in
                            try await VersionLookup.getVersionMetadata(account: &userAccount.account, app: app, versionID: version)
                        }
                        self.versionItems[version] = metadata
                    } catch {
                        failures.append("\(version): \(error.localizedDescription)")
                    }
                }
                self.error = failures.isEmpty ? nil : failures.joined(separator: "\n")
            self.loading = false
        }
    }

    func populateVersionItem(for versionID: String) {
        guard let accountIdentifier, !loading, versionIdentifiers.contains(versionID), versionItems[versionID] == nil else { return }
        loading = true
        error = nil

        Task {
            do {
                let app = self.package.software
                let metadata = try await AppStore.this.withAccount(id: accountIdentifier) { userAccount in
                    try await VersionLookup.getVersionMetadata(account: &userAccount.account, app: app, versionID: versionID)
                }
                self.versionItems[versionID] = metadata
            } catch {
                self.error = error.localizedDescription
            }
            self.loading = false
        }
    }
}

extension AppPackageArchive {
    var version: String {
        package.software.version
    }

    var releaseDate: Date? {
        package.releaseDate
    }

    var releaseNotes: String? {
        package.software.releaseNotes
    }

    var formattedPrice: String? {
        package.software.formattedPrice
    }

    var price: Double? {
        package.software.price
    }

    var downloadOutput: DownloadOutput? {
        get { package.downloadOutput }
        set { package.downloadOutput = newValue }
    }
}
