//
//  VersionLookup.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation
import CoreFoundation

public enum VersionLookup {
    public static func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String
    ) async throws -> VersionMetadata {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let dict = try await StoreDownloadEndpoint.fetchProductWithFallback(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: Configuration.deviceIdentifier,
            externalVersionID: versionID
        )

        return try await metadata(from: dict, app: app, versionID: versionID) { url in
            try await RemoteIPAReader.metadata(url: url, bundleID: app.bundleID)
        }
    }

    static func metadata(from response: [String: Any], app: Software, versionID: String,
        readIPA: (URL) async throws -> VersionMetadata) async throws -> VersionMetadata {
        try ApplePackageError.checkSession(response)
        if StoreDownloadEndpoint.failureType(in: response) == "9610" { throw ApplePackageError.licenseRequired }
        try StoreDownloadEndpoint.validateVersionedResponse(response, app: app, version: versionID)
        guard let items = response["songList"] as? [[String: Any]], let item = items.first,
              let url = (item["URL"] as? String).flatMap(URL.init(string:)) else { try ensureFailed(Strings.missingDownloadURL) }
        // Do not use bundleShortVersionString/releaseDate from the response:
        // Apple can return stale values even for a correctly pinned version ID.
        return try await readIPA(url)
    }

    static func parseReleaseDate(_ value: Any?) -> Date? {
        // XML plist <date> becomes Foundation.Date, unlike <string> dates.
        if let date = value as? Date { return date }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let seconds = number.doubleValue
            guard seconds.isFinite, seconds >= Double(Int64.min), seconds < Double(Int64.max) else { return nil }
            return Date(timeIntervalSince1970: seconds.rounded(.towardZero))
        }
        guard let raw = value as? String else { return nil }
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        for format in ["yyyy-MM-dd", "EEEE, MMMM d, yyyy"] {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = format
            parser.isLenient = false
            if let date = parser.date(from: string) { return date }
        }
        return nil
    }
}
