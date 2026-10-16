//
//  PackageManifest.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/13.
//

import ApplePackage
import Combine
import Foundation

private let packagesDir = {
    let ret = documentsDirectory.appendingPathComponent("Packages")
    try? FileManager.default.createDirectory(at: ret, withIntermediateDirectories: true)
    return ret
}()

class PackageManifest: ObservableObject, Identifiable, Codable, Hashable, Equatable {
    // Downloads need attribution, never the login password, token or cookies.
    // Keeping the old nested keys also decodes existing download manifests.
    struct AccountSummary: Codable {
        struct Details: Codable {
            var email: String
            var store: String
        }
        var account: Details
        var id: String { account.email }
        var regionCode: String { ApplePackage.Configuration.countryCode(for: account.store) ?? account.store }
        var regionName: String { AppStore.UserAccount.regionName(for: regionCode) }

        init(_ user: AppStore.UserAccount) {
            account = Details(email: user.account.email, store: user.account.store)
        }
    }

    private(set) var id: UUID = .init()

    private(set) var account: AccountSummary?
    private(set) var package: AppStore.AppPackage
    private(set) var localIPA: LocalIPAInfo?
    @Published var displayName: String = ""

    var isLocal: Bool { localIPA != nil }
    var installationBundleVersion: String { localIPA?.buildVersion ?? package.software.version }

    var displayPackage: AppStore.AppPackage {
        var result = package
        if !displayName.isEmpty { result.software.name = displayName }
        return result
    }

    private(set) var url: URL
    private(set) var signatures: [ApplePackage.Sinf]
    private(set) var iTunesMetadata: Data

    private(set) var creation: Date

    @Published var state: PackageState = .init()

    var targetLocation: URL {
        if isLocal {
            return packagesDir.appendingPathComponent("Local").appendingPathComponent("\(id.uuidString).ipa")
        }
        return packagesDir
            .appendingPathComponent(package.software.bundleID)
            .appendingPathComponent(package.software.version)
            .appendingPathComponent("\(id.uuidString)")
            .appendingPathExtension("ipa")
    }

    var completed: Bool {
        state.status == .completed
    }

    func updateLocalIPAInfo(_ info: LocalIPAInfo) {
        guard isLocal else { return }
        objectWillChange.send()
        localIPA = info
    }

    func waitForCompletion(timeout: TimeInterval? = nil) async {
        let start = Date().timeIntervalSince1970
        while true {
            if let timeout, Date().timeIntervalSince1970 - start > timeout {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(5e8))
            // .paused is terminal for waiters: a user-paused download will not
            // progress on its own, so the update flow must not spin forever.
            if [.failed, .completed, .paused].contains(state.status) {
                return
            }
        }
    }

    init(account: AppStore.UserAccount, package: AppStore.AppPackage, downloadOutput: ApplePackage.DownloadOutput) throws {
        self.account = AccountSummary(account)
        self.package = package
        guard let url = URL(string: downloadOutput.downloadURL) else {
            throw NSError(
                domain: "Asspp.Download",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid download URL: \(downloadOutput.downloadURL)"],
            )
        }
        self.url = url
        signatures = downloadOutput.sinfs
        iTunesMetadata = downloadOutput.iTunesMetadata
        creation = .init()
    }

    init(localIPA info: LocalIPAInfo, displayName: String) {
        account = nil
        localIPA = info
        self.displayName = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        package = AppStore.AppPackage(software: ApplePackage.Software(id: 0, bundleID: info.bundleID,
            name: info.name, version: info.version, artistName: "", sellerName: info.signing.teamName ?? "",
            description: "", averageUserRating: 0, userRatingCount: 0, artworkUrl: "", screenshotUrls: [],
            minimumOsVersion: info.minimumOSVersion, fileSizeBytes: String(info.fileSize), releaseDate: "", primaryGenreName: ""))
        url = URL(fileURLWithPath: info.originalFileName)
        signatures = []
        iTunesMetadata = Data()
        creation = Date()
        state.complete()
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        account = try container.decodeIfPresent(AccountSummary.self, forKey: .account)
        package = try container.decode(AppStore.AppPackage.self, forKey: .package)
        localIPA = try container.decodeIfPresent(LocalIPAInfo.self, forKey: .localIPA)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        url = try container.decode(URL.self, forKey: .url)
        signatures = try container.decode([ApplePackage.Sinf].self, forKey: .signatures)
        iTunesMetadata = try container.decodeIfPresent(Data.self, forKey: .iTunesMetadata) ?? Data()
        creation = try container.decode(Date.self, forKey: .creation)
        state = try container.decode(PackageState.self, forKey: .runtime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(account, forKey: .account)
        try container.encode(package, forKey: .package)
        try container.encodeIfPresent(localIPA, forKey: .localIPA)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(url, forKey: .url)
        try container.encode(signatures, forKey: .signatures)
        try container.encode(iTunesMetadata, forKey: .iTunesMetadata)
        try container.encode(creation, forKey: .creation)
        try container.encode(state, forKey: .runtime)
    }

    private enum CodingKeys: String, CodingKey {
        case id, account, package, localIPA, displayName, url, signatures, iTunesMetadata, creation, runtime
    }

    // Identity is the immutable UUID; hashing mutable fields like `state` would
    // change a manifest's hash mid-download and break Set/Dictionary lookups.
    static func == (lhs: PackageManifest, rhs: PackageManifest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension PackageManifest {
    func delete() {
        try? FileManager.default.removeItem(at: targetLocation)
        var cleanUpDir = targetLocation.deletingLastPathComponent()
        do {
            while FileManager.default.fileExists(atPath: cleanUpDir.path),
                  try FileManager.default.contentsOfDirectory(atPath: cleanUpDir.path).isEmpty,
                  cleanUpDir.path != packagesDir.path,
                  cleanUpDir.path.count > packagesDir.path.count,
                  cleanUpDir.path.contains(packagesDir.path)
            {
                try? FileManager.default.removeItem(at: cleanUpDir)
                cleanUpDir.deleteLastPathComponent()
            }
        } catch {}
    }
}
