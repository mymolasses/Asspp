@testable import ApplePackage
import Foundation
import XCTest

final class StoreDownloadEndpointTests: XCTestCase {
    func testUpdateProductEndpointPreservesBagQueryAndSetsGuid() throws {
        let bagURL = try XCTUnwrap(URL(string: "https://downloaddispatch.itunes.apple.com/up/updateProduct?caller=Configurator"))
        let url = try StoreDownloadEndpoint.updateProduct(bagURL).url(
            pod: nil,
            deviceIdentifier: "aabbccddeeff"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "downloaddispatch.itunes.apple.com")
        XCTAssertEqual(components.path, "/up/updateProduct")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "caller" })?.value, "Configurator")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "guid" })?.value, "aabbccddeeff")
    }

    func testUpdateProductUsesExternalVersionIdPayloadKey() {
        let endpoint = StoreDownloadEndpoint.updateProduct(
            URL(string: "https://downloaddispatch.itunes.apple.com/up/updateProduct")!
        )
        XCTAssertEqual(endpoint.externalVersionIDKey, "externalVersionId")
    }
}
