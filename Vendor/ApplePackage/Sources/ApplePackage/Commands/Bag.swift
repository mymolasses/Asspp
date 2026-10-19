//
//  Bag.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import AsyncHTTPClient
import Foundation
import NIOCore

public enum Bag {
    public struct BagOutput {
        public var authEndpoint: URL
        public var updateProductEndpoint: URL?
        public var entDownloadEndpoint: URL? = nil
        public var redownloadEndpoint: URL? = nil
        public var sapSetup: String? = nil
        public var sapCertificate: String? = nil
        public var sapVersion: UInt32? = nil
    }

    private static let defaultAuthEndpoint = "https://auth.itunes.apple.com/auth/v1/native/fast/"

    public static func fetchBag() async throws -> BagOutput {
        let deviceIdentifier = Configuration.deviceIdentifier.uppercased()

        let client = Configuration.makeHTTPClient(redirectConfiguration: .follow(max: 8, allowCycles: false))
        defer { _ = client.shutdown() }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "init.itunes.apple.com"
        comps.path = "/bag.xml"
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        guard let url = comps.url else {
            APLogger.debug("bag: failed to construct URL, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!, updateProductEndpoint: nil)
        }

        let headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Accept", "application/xml"),
        ]

        APLogger.logRequest(method: "GET", url: url.absoluteString, headers: headers)

        let request = try HTTPClient.Request(
            url: url.absoluteString,
            method: .GET,
            headers: .init(headers)
        )

        let deadline = NIODeadline.now() + .seconds(20)
        let response: HTTPClient.Response = try await client.execute(request: request, deadline: deadline).get()

        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes
        )

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            APLogger.debug("bag: empty response body, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!, updateProductEndpoint: nil)
        }

        let plistData = extractPlistData(from: data)

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            APLogger.debug("bag: failed to parse plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!, updateProductEndpoint: nil)
        }

        return parse(plist)
    }

    static func parse(_ plist: [String: Any]) -> BagOutput {
        let urlBag = plist["urlBag"] as? [String: Any] ?? plist
        let auth = (urlBag["authenticateAccount"] as? String) ?? (plist["authenticateAccount"] as? String)
        var output = BagOutput(authEndpoint: auth.flatMap(normalizedAuthEndpoint) ?? URL(string: defaultAuthEndpoint)!,
            updateProductEndpoint: (urlBag["updateProduct"] as? String).flatMap { downloadEndpoint($0, path: "/up/updateProduct") })
        output.redownloadEndpoint = (urlBag["redownloadProduct"] as? String).flatMap { downloadEndpoint($0, path: "/r/redownload") }
        output.entDownloadEndpoint = (urlBag["volumeStoreDownloadProduct"] as? String).flatMap {
            downloadEndpoint($0, path: "/WebObjects/DownloadDispatch.woa/wa/ent/download")
        }
        output.sapSetup = urlBag["sign-sap-setup"] as? String
        output.sapCertificate = urlBag["sign-sap-setup-cert"] as? String
        if let value = urlBag["sign-sap-version"] as? String { output.sapVersion = UInt32(value) }
        if let value = urlBag["sign-sap-version"] as? NSNumber { output.sapVersion = value.uint32Value }
        return output
    }

    /// v2.7.0 normalizes the finance auth path's trailing slash while keeping
    /// the bag host and query. Native endpoints retain their own path.
    static func normalizedAuthEndpoint(from value: String) -> URL? {
        guard var c = URLComponents(string: value), c.scheme == "https", let host = c.host?.lowercased(),
              c.user == nil, c.password == nil, c.fragment == nil,
              c.percentEncodedPath == c.path, c.port == nil || c.port == 443 else { return nil }
        let finance = "/WebObjects/MZFinance.woa/wa/authenticate"
        if host == "buy.itunes.apple.com" || host.hasSuffix("-buy.itunes.apple.com") {
            guard c.path == finance || c.path == finance + "/" else { return nil }
            c.path = finance + "/"
        } else {
            guard host == "auth.itunes.apple.com",
                  ["/auth/v1/native", "/auth/v1/native/", "/auth/v1/native/fast/"].contains(c.path) else { return nil }
        }
        return c.url
    }

    static func downloadEndpoint(_ value: String, path: String) -> URL? {
        guard let c = URLComponents(string: value), c.scheme == "https",
              c.host == "downloaddispatch.itunes.apple.com", c.port == nil,
              c.user == nil, c.password == nil, c.fragment == nil,
              c.query == nil, c.path == path, c.percentEncodedPath == path else { return nil }
        return c.url
    }

    /// The bag XML response wraps the plist inside `<Document><Protocol><plist>...</plist>`.
    /// Extract the `<plist>...</plist>` portion so PropertyListSerialization can parse it.
    /// If the data is already a bare plist, return it as-is.
    static func extractPlistData(from data: Data) -> Data {
        guard let xmlString = String(data: data, encoding: .utf8),
              let startRange = xmlString.range(of: "<plist"),
              let endRange = xmlString.range(of: "</plist>")
        else {
            return data
        }
        return Data(xmlString[startRange.lowerBound ..< endRange.upperBound].utf8)
    }
}
