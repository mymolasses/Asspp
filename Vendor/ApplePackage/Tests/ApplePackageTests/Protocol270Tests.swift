import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import XCTest
import ZIPFoundation
@testable import ApplePackage

final class Protocol270Tests: XCTestCase {
    let guid = "AABBCCDDEEFF"
    let auth = URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/")!
    var app: Software {
        Software(id: 42, bundleID: "test.app", name: "Test", version: "1", artistName: "Test", sellerName: "Test",
            description: "", averageUserRating: 0, userRatingCount: 0, artworkUrl: "", screenshotUrls: [],
            minimumOsVersion: "16", releaseDate: "", primaryGenreName: "")
    }
    var account: Account {
        Account(email: "+8613912345678", password: "private-password", appleId: "id", store: "143465-1,29",
            firstName: "Test", lastName: "", passwordToken: "private-token", directoryServicesIdentifier: "123", cookie: [], pod: "25")
    }
    var bag: Bag.BagOutput {
        Bag.parse(["urlBag": ["authenticateAccount": auth.absoluteString,
            "volumeStoreDownloadProduct": "https://downloaddispatch.itunes.apple.com" + StoreDownloadEndpoint.entPath,
            "redownloadProduct": "https://downloaddispatch.itunes.apple.com/r/redownload",
            "updateProduct": "https://downloaddispatch.itunes.apple.com/up/updateProduct"]])
    }
    func response(_ dictionary: [String: Any] = [:], status: HTTPResponseStatus = .ok,
        headers: [(String, String)] = []) throws -> HTTPClient.Response {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        return HTTPClient.Response(host: "buy.itunes.apple.com", status: status, headers: .init(headers), body: ByteBuffer(bytes: data))
    }
    var loginResult: [String: Any] { ["accountInfo": ["appleId": "+8613912345678", "address": ["firstName": "Test", "lastName": ""]],
        "passwordToken": "token", "dsPersonId": "123"] }
    var downloadResult: [String: Any] { ["songList": [["URL": "https://cdn.apple.com/test.ipa",
        "metadata": ["itemId": 42, "softwareVersionExternalIdentifier": "99", "softwareVersionBundleId": "test.app"]]]] }

    func testPhoneRoutingMatchesUpstreamAndRejectsAmbiguousInputs() {
        let cases: [(String, String?)] = [
            ("13912345678", "143465"), ("+8613912345678", "143465"), ("008613912345678", "143465"),
            ("8613912345678", "143465"), (" +86 139-1234-5678 ", "143465"),
            ("9123456789", "143467"), ("8612345678", "143467"), ("6123456789", "143467"),
            ("09123456789", "143467"), ("+919123456789", "143467"), ("00919123456789", "143467"),
            ("919123456789", "143467"), ("+91 91234-56789", "143467"),
            ("person@example.test", nil), ("13912345678@example.test", nil), ("some-account", nil), ("", nil),
            (" -- ", nil), ("+", nil), ("00", nil), ("139x12345678", nil), ("139/1234/5678", nil),
            ("+８６１３９１２３４５６７８", nil), ("＋8613912345678", nil), ("139\n12345678", nil),
            ("139+12345678", nil), ("++8613912345678", nil), ("+008613912345678", nil),
            ("+13912345678", nil), ("0013912345678", nil), ("+8612345678", nil), ("+9123456789", nil),
            ("+861391234567", nil), ("+86139123456789", nil), ("8609123456789", nil),
            ("+8623912345678", nil), ("+91912345678", nil), ("+9191234567890", nil),
            ("+915123456789", nil), ("+9109123456789", nil),
        ]
        for (input, expected) in cases { XCTAssertEqual(AuthenticationInput.phoneNumberStorefront(input), expected, input) }
    }

    func testVerificationInput() throws {
        for value in ["012345", " 012 345\n", "\u{1B}[200~012345\u{1B}[201~", "0\u{2003}12345"] {
            XCTAssertEqual(try AuthenticationInput.normalizeVerificationCode(value), "012345")
        }
        XCTAssertEqual(try AuthenticationInput.normalizeVerificationCode(""), "")
        for value in [" ", "12345", "1234567", "１２３４５６", "123a45", "\u{1B}[200~123456"] {
            XCTAssertThrowsError(try AuthenticationInput.normalizeVerificationCode(value))
        }
    }

    func testRedirectPreservesSecondAttemptAndPhoneHeader() async throws {
        var bodies: [Data] = []
        var requestCount = 0
        let result = try await Authenticator.authenticate(email: "+86 139-1234-5678", password: "password", code: "", cookies: [],
            bag: bag, deviceIdentifier: guid,
            actionSignature: { data, _, _ in bodies.append(data); return "signature" }, send: { request in
                XCTAssertEqual(request.headers.first(name: "X-Apple-Store-Front"), "143465")
                XCTAssertEqual(request.headers.first(name: "X-Apple-ActionSignature"), "signature")
                requestCount += 1
                switch requestCount {
                case 1: return try self.response(["failureType": "-5000"])
                case 2: return try self.response(status: .temporaryRedirect,
                    headers: [("Location", "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/?routing=test")])
                default: return try self.response(self.loginResult, headers: [("x-set-apple-store-front", "143465")])
                }
            }, sleep: { _ in XCTFail("No retry expected") })
        XCTAssertEqual(result.directoryServicesIdentifier, "123")
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[1], bodies[2])
        let payload = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodies[2], format: nil) as? [String: String])
        XCTAssertEqual(payload["attempt"], "2")
        XCTAssertEqual(payload["appleId"], "+86 139-1234-5678")
    }

    func testTransportRetryIsBoundedAndDoesNotRetryCancellationOrSigning() async throws {
        var sends = 0
        var delays: [TimeInterval] = []
        do {
            _ = try await Authenticator.authenticate(email: "test@invalid", password: "p", code: "", cookies: [], bag: bag,
                deviceIdentifier: guid, actionSignature: nil, send: { _ in sends += 1; throw HTTPClientError.remoteConnectionClosed },
                sleep: { delays.append($0) })
            XCTFail("Expected exhausted retries")
        } catch { XCTAssertEqual(error as? HTTPClientError, .remoteConnectionClosed) }
        XCTAssertEqual(sends, 3)
        XCTAssertEqual(delays, [10, 20])
        XCTAssertFalse(Authenticator.isRetryableTransportError(CancellationError()))
        XCTAssertFalse(Authenticator.isRetryableTransportError(URLError(.serverCertificateUntrusted)))
        XCTAssertTrue(Authenticator.isRetryableTransportError(URLError(.networkConnectionLost)))
        sends = 0
        do {
            _ = try await Authenticator.authenticate(email: "a", password: "p", code: "", cookies: [], bag: bag,
                deviceIdentifier: guid, actionSignature: { _, _, _ in throw URLError(.timedOut) },
                send: { _ in sends += 1; return try self.response() }, sleep: { _ in XCTFail() })
            XCTFail()
        } catch {}
        XCTAssertEqual(sends, 0)
    }

    func testHTTPRetryDistinguishesAppleErrorsFromHTML403() throws {
        XCTAssertTrue(Authenticator.shouldRetryResponse(status: 403, location: nil, body: Data("<html>blocked</html>".utf8)))
        let error = try PropertyListSerialization.data(fromPropertyList: ["failureType": "5005"], format: .xml, options: 0)
        XCTAssertFalse(Authenticator.shouldRetryResponse(status: 403, location: nil, body: error))
        var cookies: [Cookie] = []; var store = ""; var pod: String?
        XCTAssertThrowsError(try Authenticator.parseResponse(response(["customerMessage": "MZFinance.BadLogin.Configurator_message"]),
            endpoint: auth, email: "test", password: "p", code: "123456", cookies: &cookies, storeFront: &store, pod: &pod, attempt: 1)) {
            guard case ApplePackageError.invalidVerificationCode = $0 else { return XCTFail("Unexpected error") }
        }
    }

    func testBagTrustAndPathNormalization() {
        XCTAssertEqual(Bag.normalizedAuthEndpoint(from: String(auth.absoluteString.dropLast()))?.path, auth.path)
        XCTAssertEqual(Bag.normalizedAuthEndpoint(from: auth.absoluteString + "?routing=opaque")?.query, "routing=opaque")
        XCTAssertNotNil(bag.entDownloadEndpoint)
        for value in ["https://evil.invalid" + StoreDownloadEndpoint.entPath,
            "http://downloaddispatch.itunes.apple.com" + StoreDownloadEndpoint.entPath,
            "https://user@downloaddispatch.itunes.apple.com" + StoreDownloadEndpoint.entPath,
            "https://downloaddispatch.itunes.apple.com:444" + StoreDownloadEndpoint.entPath,
            "https://downloaddispatch.itunes.apple.com" + StoreDownloadEndpoint.entPath + "?token=x"] {
            XCTAssertNil(Bag.downloadEndpoint(value, path: StoreDownloadEndpoint.entPath))
        }
        for value in ["https://evil.itunes.apple.com/auth", "https://buy.itunes.apple.com/other",
            "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/%61uthenticate"] {
            XCTAssertNil(Bag.normalizedAuthEndpoint(from: value))
        }
        XCTAssertThrowsError(try Authenticator.redirectURL(status: 303, location: auth.absoluteString, from: auth)) // must reject 303 explicitly
    }

    func testKBSyncPreferredThenCachedWithoutRegeneration() async throws {
        let cache = DownloadKBSyncCache()
        var generated = 0; var sent = 0; var acc = account
        for _ in 0..<2 {
            _ = try await StoreDownloadEndpoint.fetchProductWithFallback(account: &acc, app: app,
                deviceIdentifier: guid, externalVersionID: "99", bag: bag,
                provider: { device, dsid in XCTAssertEqual(device, self.guid); XCTAssertEqual(dsid, "123"); generated += 1; return Data([1, 2]) },
                cache: cache, resolveVersion: { XCTFail(); return "" }, send: { request, _ in
                    sent += 1
                    XCTAssertEqual(request.url.path, StoreDownloadEndpoint.entPath)
                    XCTAssertEqual(request.headers.first(name: "X-Token"), "private-token")
                    XCTAssertEqual(request.headers.first(name: "X-Apple-Store-Front"), self.account.store)
                    return try self.response(self.downloadResult)
                })
        }
        XCTAssertEqual(generated, 1); XCTAssertEqual(sent, 2)
    }

    func testRejectedCacheRegeneratesOnceAndSeparatesDevices() async throws {
        let cache = DownloadKBSyncCache(); let key = "123:" + guid
        await cache.store(Data([0]), for: key)
        var acc = account; var sent = 0; var generated = 0
        _ = try await StoreDownloadEndpoint.fetchProductWithFallback(account: &acc, app: app,
            deviceIdentifier: guid, externalVersionID: "99", bag: bag,
            provider: { _, _ in generated += 1; return Data([1]) }, cache: cache,
            resolveVersion: { "99" }, send: { _, _ in
                sent += 1
                return try self.response(sent == 1 ? ["failureType": "5002"] : self.downloadResult)
            })
        XCTAssertEqual(generated, 1); XCTAssertEqual(sent, 2)
        let stored = await cache.value(for: key); XCTAssertEqual(stored, Data([1]))
        await cache.invalidate(key: key, value: Data([0]))
        let retained = await cache.value(for: key); XCTAssertEqual(retained, Data([1]))
        let other = await cache.value(for: "124:" + guid); XCTAssertNil(other)
    }

    func testDownloadRecoveryRetainsCredentialsAndVersion() async throws {
        var acc = account; var paths: [String] = []
        _ = try await StoreDownloadEndpoint.fetchProductWithFallback(account: &acc, app: app,
            deviceIdentifier: guid, externalVersionID: "99", bag: bag,
            provider: { _, _ in throw URLError(.timedOut) }, cache: DownloadKBSyncCache(), resolveVersion: { "99" },
            send: { request, _ in
                paths.append(request.url.path)
                XCTAssertEqual(request.headers.first(name: "X-Dsid"), "123")
                XCTAssertNil(request.headers.first(name: "X-Token"))
                switch paths.count {
                case 1: return try self.response(["customerMessage": "App No Longer Available"])
                case 2: return HTTPClient.Response(host: "downloaddispatch.itunes.apple.com", status: .internalServerError, headers: .init(), body: nil)
                default: return try self.response(self.downloadResult)
                }
            })
        XCTAssertEqual(paths, ["/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct", "/r/redownload", "/up/updateProduct"])
    }

    func testCancellationDoesNotRegenerateOrEnterLegacyChain() async throws {
        var acc = account; let cache = DownloadKBSyncCache(); var generated = 0; var sent = 0
        await cache.store(Data([1]), for: "123:" + guid)
        do {
            _ = try await StoreDownloadEndpoint.fetchProductWithFallback(account: &acc, app: app,
                deviceIdentifier: guid, externalVersionID: "99", bag: bag,
                provider: { _, _ in generated += 1; return Data([2]) }, cache: cache,
                resolveVersion: { "99" }, send: { _, _ in sent += 1; throw CancellationError() })
            XCTFail("Cancellation must escape")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(generated, 0); XCTAssertEqual(sent, 1)
    }

    func testFreshBlobFailureDoesNotRegenerateAgainOrCacheFailure() async throws {
        var acc = account; let cache = DownloadKBSyncCache(); var generated = 0; var sent = 0
        _ = try await StoreDownloadEndpoint.fetchProductWithFallback(account: &acc, app: app,
            deviceIdentifier: guid, externalVersionID: "99", bag: bag,
            provider: { _, _ in generated += 1; return Data([2]) }, cache: cache,
            resolveVersion: { "99" }, send: { request, _ in
                sent += 1
                if request.url.path == StoreDownloadEndpoint.entPath { return try self.response(["failureType": "5002"]) }
                return try self.response(self.downloadResult)
            })
        XCTAssertEqual(generated, 1); XCTAssertEqual(sent, 2)
        let stored = await cache.value(for: "123:" + guid); XCTAssertNil(stored)
    }

    func testEntNeverFollowsRedirectWithToken() async throws {
        var acc = account; var sent = 0
        do {
            _ = try await StoreDownloadEndpoint.ent(bag.entDownloadEndpoint!).fetchProduct(account: &acc, app: app,
                deviceIdentifier: guid, externalVersionID: "99", kbsync: Data([1]), send: { _, _ in
                    sent += 1; return try self.response(status: .found, headers: [("Location", self.auth.absoluteString)])
                })
            XCTFail()
        } catch {}
        XCTAssertEqual(sent, 1)
        XCTAssertFalse(StoreDownloadEndpoint.trustedRedirect(URL(string: "https://attacker.invalid/r/redownload")!))
        XCTAssertFalse(StoreDownloadEndpoint.trustedRedirect(URL(string: "https://user:pass@buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct")!))
    }

    func testDownloadIdentityAndResponseValidation() throws {
        for pair in [("ABC", "123"), (guid, "0"), (guid, "-1"), (guid, "18446744073709551616")] {
            XCTAssertThrowsError(try StoreDownloadEndpoint.validateKBSyncIdentity(guid: pair.0, dsid: pair.1))
        }
        XCTAssertNoThrow(try StoreDownloadEndpoint.validateVersionedResponse(downloadResult, app: app, version: "99"))
        XCTAssertThrowsError(try StoreDownloadEndpoint.validateVersionedResponse(downloadResult, app: app, version: "100"))
        XCTAssertThrowsError(try StoreDownloadEndpoint.validateVersionedResponse(["songList": []], app: app, version: "99"))
        XCTAssertTrue(StoreDownloadEndpoint.needsFallback(["failureType": "5002"]))
        XCTAssertFalse(StoreDownloadEndpoint.needsFallback(["failureType": "9610"]))
        XCTAssertFalse(StoreDownloadEndpoint.needsFallback(["customerMessage": "Account disabled"]))
    }

    func testWirePayloadUsesKBSyncSerialAndEndpointVersionKeys() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { group.shutdownGracefully { _ in } }
        let endpoints: [(StoreDownloadEndpoint, String)] = [(.ent(bag.entDownloadEndpoint!), "externalVersionId"),
            (.redownloadAt(bag.redownloadEndpoint!), "appExtVrsId"), (.updateProduct(bag.updateProductEndpoint!), "appExtVrsId")]
        for (endpoint, versionKey) in endpoints {
            let isEnt = versionKey == "externalVersionId"
            let request = try endpoint.makeRequest(account: account, app: app,
                url: endpoint.url(pod: "25", deviceIdentifier: guid), guid: guid,
                externalVersionID: "99", kbsync: isEnt ? Data([1, 2, 3]) : nil)
            let buffer = PayloadBuffer()
            try await request.body!.stream(.init { io in
                if case let .byteBuffer(bytes) = io { buffer.append(Data(bytes.readableBytesView)) }
                return group.next().makeSucceededFuture(())
            }).get()
            let payload = try XCTUnwrap(PropertyListSerialization.propertyList(from: buffer.data, format: nil) as? [String: Any])
            XCTAssertEqual(payload[versionKey] as? String, "99")
            XCTAssertEqual(payload["guid"] as? String, guid)
            if isEnt {
                XCTAssertEqual(payload["kbsync"] as? String, "AQID")
                XCTAssertEqual(Data(base64Encoded: payload["serialNumber"] as! String), Data([0x54, 0xc8, 0xb0, 0xa9, 0x88, 0xcc, 0xdd, 0xee, 0xff]))
                XCTAssertEqual(payload["salableAdamId"] as? String, "42")
            } else { XCTAssertNil(payload["kbsync"]) }
        }
    }

    func testWrongPlatformAndBundleAreRejectedBeforeFinalization() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (index, pair) in [("iPhoneOS", "test.app"), ("AppleTVOS", "test.app"), ("iPhoneOS", "wrong.app")].enumerated() {
            let file = folder.appendingPathComponent("test-\(index).ipa")
            let archive = try Archive(url: file, accessMode: .create)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": pair.1,
                "CFBundleSupportedPlatforms": [pair.0]], format: .binary, options: 0)
            try archive.addEntry(with: "Payload/Test.app/Info.plist", type: .file, uncompressedSize: Int64(data.count),
                provider: { position, size in data.subdata(in: Int(position)..<min(data.count, Int(position) + size)) })
            if index == 0 { XCTAssertNoThrow(try SignatureInjector.validateMobilePackage(at: file, expectedBundleID: "test.app")) }
            else { XCTAssertThrowsError(try SignatureInjector.validateMobilePackage(at: file, expectedBundleID: "test.app")) }
        }
    }

    func testExplicitEmptyFailureTypeHasSuccessSemantics() throws {
        var result = downloadResult
        result["failureType"] = ""
        result["customerMessage"] = ""
        XCTAssertNoThrow(try StoreDownloadEndpoint.validateVersionedResponse(result, app: app, version: "99"))
        XCTAssertFalse(StoreDownloadEndpoint.needsFallback(result))
        XCTAssertTrue(StoreDownloadEndpoint.needsFallback(["failureType": "", "songList": []]))
        XCTAssertTrue(StoreDownloadEndpoint.needsFallback(["failureType": "", "customerMessage": "No Longer Available"]))
    }

    func testConsumerCatalogFallbackKeepsRegionAndChecksPlatform() async throws {
        var urls: [URL] = []
        let data: [String: Any] = ["data": [["id": "42", "type": "apps", "attributes": [
            "deviceFamilies": ["iphone"], "platformAttributes": ["ios": ["bundleId": "test.app", "externalVersionId": 99]]]]]]
        let json = try JSONSerialization.data(withJSONObject: data)
        let metadata = try await PlatformVersionLookup.lookup(appID: 42, countryCode: "CN", entityType: .iPhone) { request in
            urls.append(request.url)
            return request.url.host == "apps.apple.com" ? json : Data("{\"results\":{}}".utf8)
        }
        XCTAssertEqual(metadata.externalVersionID, "99")
        XCTAssertEqual(urls.count, 4)
        XCTAssertTrue(urls.last!.path.contains("/catalog/cn/apps/42"))
        XCTAssertThrowsError(try PlatformVersionLookup.parseIOSCatalog(json, appID: 43, entityType: .iPhone))
        XCTAssertThrowsError(try PlatformVersionLookup.parseIOSCatalog(json, appID: 42, entityType: .iPad))
    }
}

private final class PayloadBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; bytes.append(data) }
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
}
