//
//  AppPackageArchive.swift
//  Asspp
//
//  Created by luca on 15.09.2025.
//

import ApplePackage
import Combine
import Foundation

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
    @Published var versionItems: [VersionIdentifier: VersionMetadata] = [:]

    @Published var error: String?
    @Published var loading = false
    @Published var shouldDismiss = false
    @Published private(set) var loadingVersionIDs: Set<String> = []
    @Published private(set) var versionErrors: [String: String] = [:]
    private var generation = UUID()

    typealias ListVersions = (String, Software) async throws -> [String]
    typealias LoadVersion = (String, Software, String) async throws -> VersionMetadata
    private let listVersions: ListVersions
    private let loadVersion: LoadVersion

    init(accountID: String?, region: String, package: AppStore.AppPackage,
         listVersions: @escaping ListVersions = { accountID, software in
             try await AppStore.this.withAccount(id: accountID) { user in
                 try await VersionFinder.list(account: &user.account, bundleIdentifier: software.bundleID, software: software)
             }
         },
         loadVersion: @escaping LoadVersion = { accountID, software, versionID in
             try await AppStore.this.withAccount(id: accountID) { user in
                 try await VersionLookup.getVersionMetadata(account: &user.account, app: software, versionID: versionID)
             }
         }) {
        accountIdentifier = accountID
        self.region = region
        self.package = package
        self.listVersions = listVersions
        self.loadVersion = loadVersion
    }

    func package(for externalVersion: String) -> AppStore.AppPackage? {
        if let metadata = versionItems[externalVersion] {
            var pkg = package
            pkg.software.version = metadata.displayVersion
            pkg.releaseDate = metadata.releaseDate
            pkg.externalVersionID = externalVersion
            return pkg
        } else {
            return nil
        }
    }

    func populateVersionIdentifiers() {
        guard let accountIdentifier, !loading else { return }
        // Refresh invalidates in-flight details so an old request cannot refill
        // the refreshed list or clear a newer row's loading indicator.
        let requestGeneration = UUID()
        generation = requestGeneration
        versionIdentifiers = []
        versionItems = [:]
        loadingVersionIDs = []
        versionErrors = [:]
        loading = true
        error = nil
        let software = package.software

        Task {
            do {
                let versions = try await listVersions(accountIdentifier, software)
                guard generation == requestGeneration else { return }
                var seen = Set<String>()
                versionIdentifiers = versions.reversed().filter { seen.insert($0).inserted }
            } catch {
                guard generation == requestGeneration else { return }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    func populateVersionItem(for versionID: String) {
        guard let accountIdentifier, !loading, versionIdentifiers.contains(versionID),
              versionItems[versionID] == nil, !loadingVersionIDs.contains(versionID) else { return }
        let requestGeneration = generation
        let software = package.software
        loadingVersionIDs.insert(versionID)
        versionErrors[versionID] = nil

        Task {
            do {
                let metadata = try await loadVersion(accountIdentifier, software, versionID)
                guard generation == requestGeneration else { return }
                versionItems[versionID] = metadata
            } catch {
                guard generation == requestGeneration else { return }
                versionErrors[versionID] = error.localizedDescription
            }
            loadingVersionIDs.remove(versionID)
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
