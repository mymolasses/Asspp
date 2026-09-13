import Foundation
import XCTest
@testable import ApplePackage

final class HistoricalDateTests: XCTestCase {
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
