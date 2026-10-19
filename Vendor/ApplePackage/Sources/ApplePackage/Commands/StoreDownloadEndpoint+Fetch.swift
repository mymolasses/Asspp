import AsyncHTTPClient
import Foundation
import NIOCore
import Security

/// Match the ipatool v2.7.0 recovery chain while keeping the account and GUID
/// unchanged for every request. X-Token is restricted to a bag-validated endpoint.
extension StoreDownloadEndpoint {
    static let entPath = "/WebObjects/DownloadDispatch.woa/wa/ent/download"
    typealias Transport = (HTTPClient.Request, NIODeadline) async throws -> HTTPClient.Response

    static func fetchProductWithFallback(
        client: HTTPClient, account: inout Account, app: Software,
        deviceIdentifier: String, externalVersionID: String
    ) async throws -> [String: Any] {
        let country = Configuration.countryCode(for: account.store)
        let store = account.store
        let bag = try? await Bag.fetchBag()
        try Task.checkCancellation()
        return try await fetchProductWithFallback(account: &account, app: app,
            deviceIdentifier: deviceIdentifier.uppercased(), externalVersionID: externalVersionID,
            bag: bag, provider: Configuration.kbsyncProvider, cache: .shared,
            resolveVersion: {
                guard let country else {
                    try ensureFailed(Strings.unsupportedStoreIdentifier(store))
                }
                let metadata: PlatformVersionMetadata
                do {
                    metadata = try await PlatformVersionLookup.lookup(appID: app.id, countryCode: country, entityType: .iPhone)
                } catch {
                    try Task.checkCancellation()
                    if Self.isCancellation(error) { throw error }
                    // The native package library serves both iPhone and iPad;
                    // an iPad-only consumer listing may have no iPhone offer.
                    metadata = try await PlatformVersionLookup.lookup(appID: app.id, countryCode: country, entityType: .iPad)
                }
                guard app.bundleID.isEmpty || metadata.bundleID == app.bundleID else {
                    try ensureFailed("版本目录返回了不同的 App。")
                }
                return metadata.externalVersionID
            }, send: { request, deadline in
                try await client.execute(request: request, deadline: deadline).get()
            })
    }

    static func fetchProductWithFallback(
        account: inout Account, app: Software, deviceIdentifier: String, externalVersionID: String,
        bag: Bag.BagOutput?, provider: ((String, String) async throws -> Data)?,
        cache: DownloadKBSyncCache, resolveVersion: () async throws -> String, send: Transport
    ) async throws -> [String: Any] {
        let guid = deviceIdentifier.uppercased()
        var version = externalVersionID
        if let endpoint = bag?.entDownloadEndpoint, let provider {
            do {
                if version.isEmpty { version = try await resolveVersion() }
                guard !version.isEmpty else { try ensureFailed(Strings.missingVersionIdentifiers) }
                try validateKBSyncIdentity(guid: guid, dsid: account.directoryServicesIdentifier)
                let key = account.directoryServicesIdentifier + ":" + guid
                if let cached = await cache.value(for: key) {
                    do {
                        let result = try await StoreDownloadEndpoint.ent(endpoint).fetchProduct(account: &account, app: app,
                            deviceIdentifier: guid, externalVersionID: version, kbsync: cached, send: send)
                        try validateVersionedResponse(result, app: app, version: version)
                        return result
                    } catch {
                        try Task.checkCancellation()
                        if Self.isCancellation(error) { throw error }
                        await cache.invalidate(key: key, value: cached)
                    }
                }
                let blob = try await provider(guid, account.directoryServicesIdentifier)
                try Task.checkCancellation()
                guard !blob.isEmpty else { try ensureFailed("本地 kbsync 为空。") }
                let result = try await StoreDownloadEndpoint.ent(endpoint).fetchProduct(account: &account, app: app,
                    deviceIdentifier: guid, externalVersionID: version, kbsync: blob, send: send)
                try validateVersionedResponse(result, app: app, version: version)
                await cache.store(blob, for: key)
                return result
            } catch {
                try Task.checkCancellation()
                if Self.isCancellation(error) { throw error }
                // Never print the blob, credentials, token or response body.
                APLogger.debug("ent/download unavailable; trying legacy download endpoints")
            }
        }
        try Task.checkCancellation()
        var result = try await StoreDownloadEndpoint.volumeStore.fetchProduct(account: &account, app: app,
            deviceIdentifier: guid, externalVersionID: externalVersionID, send: send)
        guard needsFallback(result) else { return result }
        guard let endpoint = bag?.redownloadEndpoint else { return result }
        if version.isEmpty { version = try await resolveVersion() }
        guard !version.isEmpty else { try ensureFailed(Strings.missingVersionIdentifiers) }
        do {
            result = try await StoreDownloadEndpoint.redownloadAt(endpoint).fetchProduct(account: &account, app: app,
                deviceIdentifier: guid, externalVersionID: version, send: send)
            if !needsFallback(result) {
                if result["failureType"] == nil { try validateVersionedResponse(result, app: app, version: version) }
                return result
            }
        } catch let error as DownloadHTTPFailure where error.status == 500 && error.emptyBody {
            // Only an empty HTTP 500 permits the updateProduct recovery.
        }
        if let endpoint = bag?.updateProductEndpoint {
            result = try await StoreDownloadEndpoint.updateProduct(endpoint).fetchProduct(account: &account, app: app,
                deviceIdentifier: guid, externalVersionID: version, send: send)
            if result["failureType"] == nil { try validateVersionedResponse(result, app: app, version: version) }
        }
        return result
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled ||
            (error as? HTTPClientError) == .cancelled
    }

    static func needsFallback(_ result: [String: Any]) -> Bool {
        if result["failureType"].map({ String(describing: $0) }) == retryableFailureType { return true }
        guard result["failureType"] == nil else { return false }
        if let items = result["songList"], !(items is [Any]) { return false }
        guard (result["songList"] as? [Any] ?? []).isEmpty else { return false }
        let message = (result["customerMessage"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return message.isEmpty || message == "no longer available" || message.hasSuffix(" no longer available")
    }

    static func validateKBSyncIdentity(guid: String, dsid: String) throws {
        guard guid.utf8.count == 12, guid.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
              let id = UInt64(dsid), id > 0 else { try ensureFailed("kbsync 需要六字节设备 GUID 和有效数字 DSID。") }
    }

    static func validateVersionedResponse(_ result: [String: Any], app: Software, version: String) throws {
        try ApplePackageError.checkSession(result)
        guard result["failureType"] == nil, result["customerMessage"] as? String ?? "" == "",
              let items = result["songList"] as? [[String: Any]], items.count == 1,
              let metadata = items[0]["metadata"] as? [String: Any],
              metadata["itemId"].map({ String(describing: $0) }) == String(app.id),
              metadata["softwareVersionExternalIdentifier"].map({ String(describing: $0) }) == version,
              let bundle = metadata["softwareVersionBundleId"] as? String, !bundle.isEmpty,
              app.bundleID.isEmpty || bundle == app.bundleID,
              let url = (items[0]["URL"] as? String).flatMap(URL.init(string:)),
              url.scheme == "https", url.host != nil else {
            try ensureFailed("下载响应与请求的 App、版本或包地址不匹配。")
        }
    }

    func fetchProduct(client: HTTPClient, account: inout Account, app: Software,
        deviceIdentifier: String, externalVersionID: String,
        deadline: NIODeadline = .now() + .seconds(45)) async throws -> [String: Any] {
        try await fetchProduct(account: &account, app: app, deviceIdentifier: deviceIdentifier,
            externalVersionID: externalVersionID, deadline: deadline,
            send: { request, deadline in try await client.execute(request: request, deadline: deadline).get() })
    }

    func fetchProduct(account: inout Account, app: Software, deviceIdentifier: String,
        externalVersionID: String, kbsync: Data? = nil,
        deadline: NIODeadline = .now() + .seconds(60), send: Transport) async throws -> [String: Any] {
        var currentURL = try url(pod: account.pod, deviceIdentifier: deviceIdentifier)
        for redirect in 0...3 {
            try Task.checkCancellation()
            let request = try makeRequest(account: account, app: app, url: currentURL,
                guid: deviceIdentifier, externalVersionID: externalVersionID, kbsync: kbsync)
            let response = try await send(request, deadline)
            account.cookie.mergeCookies(response.cookies)
            if [301, 302, 303, 307, 308].contains(Int(response.status.code)) {
                // ent/download never forwards X-Token, even to another Apple host.
                guard kbsync == nil, redirect < 3,
                      let location = response.headers.first(name: "location"),
                      let destination = URL(string: location, relativeTo: currentURL)?.absoluteURL,
                      Self.trustedRedirect(destination) else { try ensureFailed(Strings.failedToRetrieveRedirect) }
                currentURL = destination
                continue
            }
            if response.status == .unauthorized { throw ApplePackageError.sessionExpired }
            let data = response.body.map { Data($0.readableBytesView) } ?? Data()
            guard response.status == .ok else {
                throw DownloadHTTPFailure(status: Int(response.status.code), emptyBody: data.isEmpty)
            }
            guard let result = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                try ensureFailed(Strings.invalidResponse)
            }
            try ApplePackageError.checkSession(result)
            return result
        }
        try ensureFailed(Strings.failedToRetrieveRedirect)
    }

    static func trustedRedirect(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https",
              c.user == nil, c.password == nil, c.fragment == nil, c.port == nil || c.port == 443,
              c.percentEncodedPath == c.path, let host = c.host else { return false }
        if host == "downloaddispatch.itunes.apple.com" { return ["/r/redownload", "/up/updateProduct"].contains(c.path) }
        return (host == "buy.itunes.apple.com" || host.hasSuffix("-buy.itunes.apple.com")) &&
            c.path == "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
    }

    func makeRequest(account: Account, app: Software, url: URL, guid: String,
        externalVersionID: String, kbsync: Data? = nil) throws -> HTTPClient.Request {
        var payload: [String: Any] = ["creditDisplay": "", "guid": guid, "salableAdamId": app.id, "serialNumber": "0"]
        if !externalVersionID.isEmpty { payload[externalVersionIDKey] = externalVersionID }
        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"), ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier), ("X-Dsid", account.directoryServicesIdentifier),
        ]
        if let kbsync {
            try Self.validateKBSyncIdentity(guid: guid, dsid: account.directoryServicesIdentifier)
            guard Bag.downloadEndpoint(url.absoluteString.components(separatedBy: "?")[0], path: Self.entPath) != nil else {
                try ensureFailed(Strings.invalidResponse)
            }
            let bytes = stride(from: 0, to: guid.count, by: 2).map { offset -> UInt8 in
                let start = guid.index(guid.startIndex, offsetBy: offset)
                return UInt8(guid[start..<guid.index(start, offsetBy: 2)], radix: 16)!
            }
            payload["salableAdamId"] = String(app.id)
            payload["kbsync"] = kbsync.base64EncodedString()
            payload["serialNumber"] = Data([0x54, 0xc8, 0xb0, 0xa9, 0x88] + Array(bytes.suffix(4))).base64EncodedString()
            headers[0].1 = "application/x-www-form-urlencoded; charset=utf-8"
            headers[1].1 = "Configurator/2.18 (Macintosh; OS X 15.3.2; 24D81) AppleWebKit/0620.2.4.11.6"
            headers += [("X-Apple-Store-Front", account.store), ("X-Token", account.passwordToken)]
        }
        headers += account.cookie.buildCookieHeader(url)
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        return try .init(url: url, method: .POST, headers: .init(headers), body: .data(data))
    }
}

struct DownloadHTTPFailure: LocalizedError {
    var status: Int
    var emptyBody: Bool
    var errorDescription: String? { Strings.requestFailed(status: UInt(status)) }
}

/// Cache only validated blobs, isolated by account DSID and device GUID.
actor DownloadKBSyncCache {
    static let shared = DownloadKBSyncCache(persistent: true)
    private var entries: [String: Data] = [:]
    private let persistent: Bool
    private let service = (Bundle.main.bundleIdentifier ?? "wiki.qaq.Asspp") + ".kbsync-v1"
    init(persistent: Bool = false) { self.persistent = persistent }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    func value(for key: String) -> Data? {
        if let value = entries[key] { return value }
        guard persistent else { return nil }
        var request = query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, !data.isEmpty else { return nil }
        entries[key] = data
        return data
    }
    func store(_ value: Data, for key: String) {
        if entries.count >= 16, entries[key] == nil { entries.removeAll() }
        entries[key] = value
        guard persistent else { return }
        var request = query(key)
        request[kSecValueData as String] = value
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        }
    }
    func invalidate(key: String, value: Data) {
        // A concurrent request can have stored a newer blob already.
        if entries[key] == value { entries.removeValue(forKey: key) }
        guard persistent else { return }
        var request = query(key)
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, result as? Data == value {
            SecItemDelete(query(key) as CFDictionary)
        }
    }
}
