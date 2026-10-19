//
//  PlatformVersionLookup.swift
//  ApplePackage
//
//  Created by Codex on 2026/5/10.
//

import AsyncHTTPClient
import Foundation
import NIOCore

public struct PlatformVersionMetadata: Equatable, Hashable {
    public var appID: Int64
    public var bundleID: String?
    public var name: String?
    public var displayVersion: String?
    public var externalVersionID: String
    public var buyParams: String?
}

public enum PlatformVersionLookup {
    public static func lookup(
        appID: Int64,
        countryCode: String,
        entityType: EntityType
    ) async throws -> PlatformVersionMetadata {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .follow(max: 8, allowCycles: false))
        defer { _ = client.shutdown() }

        return try await lookup(appID: appID, countryCode: countryCode, entityType: entityType) { request in
            let response: HTTPClient.Response = try await client.execute(request: request, deadline: .now() + .seconds(45)).get()
            try ensure(response.status == .ok, Strings.requestFailed(status: response.status.code))
            guard let body = response.body else { try ensureFailed(Strings.responseBodyEmpty) }
            return Data(body.readableBytesView)
        }
    }

    static func lookup(appID: Int64, countryCode: String, entityType: EntityType,
        send: (HTTPClient.Request) async throws -> Data) async throws -> PlatformVersionMetadata {
        let ios = entityType == .iPhone || entityType == .iPad
        let catalogs = ios ? [entityType.metadataPlatformValue, "iphone", "ipad"] : [entityType.metadataPlatformValue]
        for catalog in catalogs {
            try Task.checkCancellation()
            let data = try await send(makeRequest(appID: appID, countryCode: countryCode, catalog: catalog))
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                try ensureFailed(Strings.invalidResponse)
            }
            guard let results = root["results"] as? [String: Any], let item = results[String(appID)] as? [String: Any],
                  let offers = item["offers"] as? [[String: Any]], let offer = offers.first else { continue }
            let version = offer["version"] as? [String: Any]
            guard let id = stringValue(version?["externalId"]) ?? externalVersionID(from: offer["buyParams"] as? String),
                  let numeric = UInt64(id), numeric > 0 else { try ensureFailed(Strings.missingVersionIdentifiers) }
            return PlatformVersionMetadata(appID: appID, bundleID: item["bundleId"] as? String,
                name: item["name"] as? String, displayVersion: version?["display"] as? String,
                externalVersionID: id, buyParams: offer["buyParams"] as? String)
        }
        guard ios else { try ensureFailed(Strings.noItemsInResponse) }
        var c = URLComponents(string: "https://apps.apple.com/api/apps/v1/catalog/\(countryCode.lowercased())/apps/\(appID)")!
        c.queryItems = [URLQueryItem(name: "platform", value: entityType == .iPad ? "ipad" : "iphone")]
        let data = try await send(HTTPClient.Request(url: c.url!, method: .GET))
        return try parseIOSCatalog(data, appID: appID, entityType: entityType)
    }

    static func parseIOSCatalog(_ data: Data, appID: Int64, entityType: EntityType) throws -> PlatformVersionMetadata {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]], items.count == 1,
              items[0]["id"] as? String == String(appID), items[0]["type"] as? String == "apps",
              let attributes = items[0]["attributes"] as? [String: Any],
              let families = attributes["deviceFamilies"] as? [String],
              families.contains(entityType == .iPad ? "ipad" : "iphone"),
              let platforms = attributes["platformAttributes"] as? [String: Any], let ios = platforms["ios"] as? [String: Any],
              let id = stringValue(ios["externalVersionId"]), let numeric = UInt64(id), numeric > 0,
              let bundle = ios["bundleId"] as? String, !bundle.isEmpty else { try ensureFailed(Strings.invalidResponse) }
        return PlatformVersionMetadata(appID: appID, bundleID: bundle, name: attributes["name"] as? String,
            displayVersion: nil, externalVersionID: id, buyParams: nil)
    }

    private static func makeRequest(appID: Int64, countryCode: String, catalog: String) throws -> HTTPClient.Request {
        var comps = URLComponents(string: "https://uclient-api.itunes.apple.com/WebObjects/MZStorePlatform.woa/wa/lookup")!
        comps.queryItems = [URLQueryItem(name: "version", value: "2"), URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "p", value: "mdm-lockup"), URLQueryItem(name: "caller", value: "MDM"),
            URLQueryItem(name: "platform", value: catalog), URLQueryItem(name: "cc", value: countryCode.lowercased()),
            URLQueryItem(name: "l", value: "en")]
        return try .init(url: comps.url!, method: .GET, headers: .init([("User-Agent", Configuration.userAgent)]))
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as Int:
            return "\(value)"
        case let value as Int64:
            return "\(value)"
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func externalVersionID(from buyParams: String?) -> String? {
        guard let buyParams,
              let comps = URLComponents(string: "applepackage://buy?\(buyParams)")
        else {
            return nil
        }
        return comps.queryItems?.first { $0.name == "appExtVrsId" }?.value
    }
}
