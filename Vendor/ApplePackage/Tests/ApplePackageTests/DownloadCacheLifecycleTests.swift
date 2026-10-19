import Foundation
import Security
import XCTest
@testable import ApplePackage

final class DownloadCacheLifecycleTests: XCTestCase {
    func testDeletionRemovesEveryDeviceOnlyForTheDeletedDSID() async throws {
        let cache = DownloadKBSyncCache()
        await cache.store(Data([1]), for: "123:DEVICE1")
        await cache.store(Data([2]), for: "123:DEVICE2")
        await cache.store(Data([3]), for: "1234:DEVICE1")
        try await cache.removeAccount(dsid: "123")
        let first = await cache.value(for: "123:DEVICE1")
        let second = await cache.value(for: "123:DEVICE2")
        let retained = await cache.value(for: "1234:DEVICE1")
        XCTAssertNil(first); XCTAssertNil(second); XCTAssertEqual(retained, Data([3]))
        try await cache.removeAccount(dsid: "123") // idempotent
    }

    func testAnInflightRequestCannotRestoreDeletedAccountCache() async throws {
        let cache = DownloadKBSyncCache()
        let old = await cache.generation(for: "123:DEVICE1")
        try await cache.removeAccount(dsid: "123")
        await cache.store(Data([1]), for: "123:DEVICE1", generation: old)
        let rejected = await cache.value(for: "123:DEVICE1")
        XCTAssertNil(rejected)
        // An explicit later login can generate a new valid blob.
        let fresh = await cache.generation(for: "123:DEVICE1")
        await cache.store(Data([2]), for: "123:DEVICE1", generation: fresh)
        let accepted = await cache.value(for: "123:DEVICE1")
        XCTAssertEqual(accepted, Data([2]))
    }

    func testDeletionCleansPersistentEntriesAcrossInstances() async throws {
        let service = "wiki.qaq.Asspp.tests.kbsync." + UUID().uuidString
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false]
        defer { SecItemDelete(base as CFDictionary) }
        for key in ["123:DEVICE1", "123:DEVICE2", "456:DEVICE1"] {
            var query = base
            query[kSecAttrAccount as String] = key
            query[kSecValueData as String] = Data([7])
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw XCTSkip("Test Keychain unavailable: \(status)") }
        }
        let cache = DownloadKBSyncCache(persistent: true, service: service)
        let seeded = await cache.value(for: "123:DEVICE1")
        XCTAssertEqual(seeded, Data([7]))
        try await cache.removeAccount(dsid: "123")
        let reopened = DownloadKBSyncCache(persistent: true, service: service)
        let first = await reopened.value(for: "123:DEVICE1")
        let second = await reopened.value(for: "123:DEVICE2")
        let retained = await reopened.value(for: "456:DEVICE1")
        XCTAssertNil(first); XCTAssertNil(second); XCTAssertEqual(retained, Data([7]))
    }
}
