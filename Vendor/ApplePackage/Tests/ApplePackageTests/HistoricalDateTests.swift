import Foundation
import XCTest
@testable import ApplePackage

final class HistoricalDateTests: XCTestCase {
    func testSessionExpiryIsTypedForHistoryAndPurchase() {
        for value in ["2034", "2042", "1008", 2034, 2042, 1008] as [Any] {
            XCTAssertThrowsError(try ApplePackageError.checkSession(["failureType": value])) { error in
                guard case ApplePackageError.sessionExpired = error else {
                    return XCTFail("Expected a recoverable session expiry")
                }
            }
        }
        XCTAssertNoThrow(try ApplePackageError.checkSession(["failureType": "9610"]))
        XCTAssertNoThrow(try ApplePackageError.checkSession(["failureType": "5002"]))
        XCTAssertNoThrow(try ApplePackageError.checkSession([:]))
    }

    func testSavedAccountRetainsSessionAcrossColdStart() throws {
        let original = Account(email: "test@example.invalid", password: "test",
            appleId: "1", store: "143463-2,34", firstName: "Test", lastName: "Account",
            passwordToken: "test-token", directoryServicesIdentifier: "1",
            cookie: [Cookie(name: "session", value: "test-cookie", path: "/", domain: ".itunes.apple.com",
                            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970, httpOnly: true, secure: true)], pod: "25")
        let restored = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.cookie.buildCookieHeader(URL(string: "https://p25-buy.itunes.apple.com/WebObjects/test")!).first?.1, "session=test-cookie")
    }

    func testStorefrontHeaderIsNotSuffixedTwice() {
        XCTAssertEqual(Purchase.storefrontHeader("143463-2,34"), "143463-2,34")
        XCTAssertEqual(Purchase.storefrontHeader("143463"), "143463-1")
    }
    func testPlistDateAndStringForms() throws {
        let expected = Date(timeIntervalSince1970: 1704067200)
        let data = try PropertyListSerialization.data(fromPropertyList: ["releaseDate": expected], format: .xml, options: 0)
        let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(VersionLookup.parseReleaseDate(decoded["releaseDate"]), expected)
        XCTAssertEqual(VersionLookup.parseReleaseDate("2024-01-01T00:00:00Z"), expected)
        XCTAssertEqual(VersionLookup.parseReleaseDate("2024-01-01T00:00:00.000Z"), expected)
        XCTAssertNil(VersionLookup.parseReleaseDate("not a date"))
        XCTAssertNil(VersionLookup.parseReleaseDate(nil))
    }
}
