//
//  AppPackage.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Foundation

extension AppStore {
    struct AppPackage: Codable, Identifiable, Hashable {
        var id: String {
            software.bundleID
        }

        var software: ApplePackage.Software
        var releaseDate: Date?
        var downloadOutput: ApplePackage.DownloadOutput?
        var externalVersionID: String?

        enum DownloadIntent: Equatable {
            case download, downloadLatest, update
        }

        /// A current-version request has no external ID; compare its displayed
        /// version instead of treating every unpinned download as the same one.
        func matchesDownload(_ requested: Self) -> Bool {
            guard id == requested.id else { return false }
            if let versionID = requested.externalVersionID {
                return externalVersionID == versionID
            }
            let version = software.version.trimmingCharacters(in: .whitespacesAndNewlines)
            return !version.isEmpty && version == requested.software.version.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func downloadIntent(comparedTo downloaded: [Self]) -> DownloadIntent {
            let versions = downloaded.filter { $0.id == id }
                .map { $0.software.version.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let newest = versions.max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) else {
                return .download
            }
            let current = software.version.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty, newest.compare(current, options: .numeric) == .orderedAscending {
                return .update
            }
            return .downloadLatest
        }

        init(software: ApplePackage.Software) {
            self.software = software
            releaseDate = ISO8601DateFormatter().date(from: software.releaseDate)
        }

        static func == (lhs: AppPackage, rhs: AppPackage) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}
