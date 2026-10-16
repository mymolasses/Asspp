import Foundation
import Security
import ZIPFoundation

struct LocalIPAInfo: Codable, Sendable {
    var originalFileName: String
    var bundleID: String
    var name: String
    var version: String
    var buildVersion: String
    var minimumOSVersion: String
    var fileSize: Int64
    var signing: SigningInfo

    struct SigningInfo: Codable, Sendable {
        enum ProfileType: String, Codable, Sendable {
            case missing, enterprise, development, adHoc, appStore

            var title: String {
                switch self {
                case .missing: String(localized: "No Provisioning Profile")
                case .enterprise: String(localized: "Enterprise")
                case .development: String(localized: "Development")
                case .adHoc: "Ad Hoc"
                case .appStore: "App Store"
                }
            }
        }

        var profileType: ProfileType
        var hasCodeResources: Bool
        var profileName: String?
        var teamName: String?
        var teamIdentifiers: [String]
        var applicationIdentifier: String?
        var expiration: Date?
        var provisionedDeviceCount: Int?
        var certificateNames: [String]

        var expired: Bool { expiration.map { $0 < Date() } ?? false }

        func matches(bundleID: String) -> Bool {
            guard let applicationIdentifier, let dot = applicationIdentifier.firstIndex(of: ".") else { return true }
            let pattern = String(applicationIdentifier[applicationIdentifier.index(after: dot)...])
            if pattern == "*" { return true }
            if pattern.hasSuffix(".*") { return bundleID.hasPrefix(String(pattern.dropLast())) }
            return pattern == bundleID
        }
    }
}

enum LocalIPAReader {
    enum Failure: LocalizedError {
        case invalidIPA, metadataTooLarge, missingMetadata, invalidMetadata

        var errorDescription: String? {
            switch self {
            case .invalidIPA: String(localized: "Choose a valid IPA file.")
            case .metadataTooLarge: String(localized: "The IPA metadata exceeds the supported size.")
            case .missingMetadata: String(localized: "The IPA must contain exactly one main app in Payload.")
            case .invalidMetadata: String(localized: "The IPA has invalid app metadata.")
            }
        }
    }

    static func read(_ url: URL, originalFileName: String) throws -> LocalIPAInfo {
        guard url.pathExtension.lowercased() == "ipa" else { throw Failure.invalidIPA }
        let archive = try Archive(url: url, accessMode: .read)
        let entries = archive.filter { entry in
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist" && entry.type == .file
        }
        guard entries.count == 1, let entry = entries.first else { throw Failure.missingMetadata }
        let data = try read(entry, from: archive, limit: 2 * 1024 * 1024)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty, bundleID.count <= 255,
              bundleID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }),
              let build = plist["CFBundleVersion"] as? String, !build.isEmpty else { throw Failure.invalidMetadata }
        let appRoot = String(entry.path.dropLast("Info.plist".count))
        let profileEntry = archive[appRoot + "embedded.mobileprovision"]
        let profileData = try profileEntry.map { try read($0, from: archive, limit: 8 * 1024 * 1024) }
        let profile = profileData.flatMap(provisioningPlist)
        let entitlements = profile?["Entitlements"] as? [String: Any] ?? [:]
        let devices = profile?["ProvisionedDevices"] as? [String]
        let type: LocalIPAInfo.SigningInfo.ProfileType
        if profile == nil { type = .missing }
        else if profile?["ProvisionsAllDevices"] as? Bool == true { type = .enterprise }
        else if devices != nil { type = entitlements["get-task-allow"] as? Bool == true ? .development : .adHoc }
        else { type = .appStore }
        let certificates = (profile?["DeveloperCertificates"] as? [Data] ?? []).compactMap { data -> String? in
            guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else { return nil }
            return SecCertificateCopySubjectSummary(certificate) as String?
        }
        let signing = LocalIPAInfo.SigningInfo(profileType: type,
            hasCodeResources: archive[appRoot + "_CodeSignature/CodeResources"] != nil,
            profileName: profile?["Name"] as? String, teamName: profile?["TeamName"] as? String,
            teamIdentifiers: profile?["TeamIdentifier"] as? [String] ?? [],
            applicationIdentifier: entitlements["application-identifier"] as? String,
            expiration: profile?["ExpirationDate"] as? Date, provisionedDeviceCount: devices?.count,
            certificateNames: certificates)
        let name = (plist["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (plist["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        return LocalIPAInfo(originalFileName: originalFileName, bundleID: bundleID, name: name,
            version: (plist["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? build,
            buildVersion: build, minimumOSVersion: plist["MinimumOSVersion"] as? String ?? "",
            fileSize: Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), signing: signing)
    }

    private static func read(_ entry: Entry, from archive: Archive, limit: Int) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= UInt64(limit) else { throw Failure.metadataTooLarge }
        var data = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard chunk.count <= limit - data.count else { throw Failure.metadataTooLarge }
            data.append(chunk)
        }
        guard checksum == entry.checksum, data.count == Int(entry.uncompressedSize) else { throw Failure.invalidIPA }
        return data
    }

    // Read the embedded XML payload like AssppWeb. This inspects metadata;
    // it does not verify the CMS signature, revocation, or Mach-O code signature.
    private static func provisioningPlist(_ data: Data) -> [String: Any]? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] { return plist }
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any]
    }
}
