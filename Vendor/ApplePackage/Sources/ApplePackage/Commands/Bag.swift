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
        public var sapSetup: String? = nil
        public var sapCertificate: String? = nil
        public var sapVersion: UInt32? = nil
    }

    private static let defaultAuthEndpoint = "https://auth.itunes.apple.com/auth/v1/native/fast/"

    public static func fetchBag() async throws -> BagOutput {
        let deviceIdentifier = Configuration.deviceIdentifier

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

        // authenticateAccount used to live inside the nested urlBag dict,
        // newer bag responses move it to the plist root
        let urlBag = plist["urlBag"] as? [String: Any] ?? [:]
        let authURLString = (plist["authenticateAccount"] as? String) ?? (urlBag["authenticateAccount"] as? String)
        let updateProductURL = (urlBag["updateProduct"] as? String).flatMap(normalizedUpdateProductEndpoint)

        guard let authURLString,
              let authURL = normalizedAuthEndpoint(from: authURLString)
        else {
            APLogger.debug("bag: no authenticateAccount in plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!, updateProductEndpoint: updateProductURL)
        }

        APLogger.info("bag: auth endpoint resolved to \(authURL)")
        var output = BagOutput(authEndpoint: authURL, updateProductEndpoint: updateProductURL)
        output.sapSetup = urlBag["sign-sap-setup"] as? String
        output.sapCertificate = urlBag["sign-sap-setup-cert"] as? String
        if let value = urlBag["sign-sap-version"] as? String { output.sapVersion = UInt32(value) }
        if let value = urlBag["sign-sap-version"] as? NSNumber { output.sapVersion = value.uint32Value }
        return output
    }

    /// The bag advertises the native auth endpoint without the `/fast/` sub-path
    /// that the login flow requires; the no-trailing-slash variant 301s to an
    /// HTML page. Legacy endpoints pass through unchanged.
    private static func normalizedAuthEndpoint(from urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        if comps.host == "auth.itunes.apple.com" {
            var path = comps.path
            while path.hasSuffix("/") {
                path.removeLast()
            }
            if !path.hasSuffix("/fast") {
                path += "/fast"
            }
            comps.path = path + "/"
        }
        return comps.url
    }

    /// Only accept the download endpoint currently advertised by Apple's bag.
    /// This prevents a malformed or intercepted bag from redirecting account
    /// cookies to an arbitrary host.
    private static func normalizedUpdateProductEndpoint(from urlString: String) -> URL? {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              url.host == "downloaddispatch.itunes.apple.com",
              url.path == "/up/updateProduct"
        else { return nil }
        return url
    }

    /// The bag XML response wraps the plist inside `<Document><Protocol><plist>...</plist>`.
    /// Extract the `<plist>...</plist>` portion so PropertyListSerialization can parse it.
    /// If the data is already a bare plist, return it as-is.
    private static func extractPlistData(from data: Data) -> Data {
        guard let xmlString = String(data: data, encoding: .utf8),
              let startRange = xmlString.range(of: "<plist"),
              let endRange = xmlString.range(of: "</plist>")
        else {
            return data
        }
        return Data(xmlString[startRange.lowerBound ..< endRange.upperBound].utf8)
    }
}
