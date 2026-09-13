import Foundation
import XCTest
@testable import ApplePackage

final class HistoricalDateTests: XCTestCase {
    func testLoginParsesBareWrappedAndBinaryPlists() throws {
        let payload: [String: Any] = ["failureType": "5005", "customerMessage": "test"]
        let xml = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        let binary = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        let wrapped = Data("<Document><Protocol>".utf8) + xml + Data("</Protocol></Document>".utf8)
        for data in [xml, binary, wrapped] {
            XCTAssertEqual(try Authenticator.decodeLoginBody(data, status: 200, contentType: "text/xml")["failureType"] as? String, "5005")
            XCTAssertFalse(Authenticator.shouldRetryResponse(status: 200, location: nil, body: data))
        }
    }

    func testMalformedLoginResponsesHaveSafeDiagnosticsAndBoundedRetryClassification() {
        for data in [Data(), Data("<html>private-token-do-not-log</html>".utf8)] {
            XCTAssertTrue(Authenticator.shouldRetryResponse(status: 200, location: nil, body: data))
            XCTAssertThrowsError(try Authenticator.decodeLoginBody(data, status: 200, contentType: "text/html")) {
                XCTAssertTrue($0.localizedDescription.contains("HTTP 200"))
                XCTAssertFalse($0.localizedDescription.contains("private-token-do-not-log"))
            }
        }
        XCTAssertTrue(Authenticator.shouldRetryResponse(status: 302, location: nil, body: nil))
        XCTAssertTrue(Authenticator.shouldRetryResponse(status: 302, location: "  ", body: nil))
        XCTAssertTrue(Authenticator.shouldRetryResponse(status: 503, location: nil, body: nil))
        XCTAssertFalse(Authenticator.shouldRetryResponse(status: 401, location: nil, body: nil))
        XCTAssertFalse(Authenticator.shouldRetryResponse(status: 302, location: "/auth", body: nil))
    }

    func testLoginRedirectResolutionAndTrustBoundary() throws {
        let base = URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate?guid=ABC")!
        let relative = try XCTUnwrap(Authenticator.redirectURL(status: 302, location: "/WebObjects/MZFinance.woa/wa/authenticate?guid=ABC", from: base))
        XCTAssertEqual(relative, base)
        XCTAssertEqual(try Authenticator.redirectURL(status: 307, location: "https://p25-buy.itunes.apple.com/auth", from: base)?.host, "p25-buy.itunes.apple.com")
        XCTAssertNil(try Authenticator.redirectURL(status: 200, location: nil, from: base))
        for location in [nil, "", "http://buy.itunes.apple.com/auth", "https://itunes.apple.com.evil.invalid/auth", "https://user:pass@buy.itunes.apple.com/auth", "https://buy.itunes.apple.com:444/auth"] as [String?] {
            XCTAssertThrowsError(try Authenticator.redirectURL(status: 302, location: location, from: base))
        }
    }

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
