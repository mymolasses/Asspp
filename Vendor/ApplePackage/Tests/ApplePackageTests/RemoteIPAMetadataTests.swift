import Foundation
import XCTest
import ZIPFoundation
@testable import ApplePackage

final class RemoteIPAMetadataTests: XCTestCase {
    private let bundle = "com.example.history"
    private let date = Date(timeIntervalSince1970: 1_704_067_200)

    private func fixture(binary: Bool = false, compression: CompressionMethod = .deflate, info: [String: Any]? = nil, noise: Int = 0) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        func add(_ path: String, data: Data, method: CompressionMethod) throws {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), modificationDate: date, compressionMethod: method) {
                position, count in data.subdata(in: Int(position)..<Int(position) + count)
            }
        }
        let info = info ?? ["CFBundleIdentifier": bundle, "CFBundleShortVersionString": "1.2.3", "CFBundleSupportedPlatforms": ["iPhoneOS"]]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: binary ? .binary : .xml, options: 0)
        try add("Payload/App.app/Info.plist", data: data, method: compression)
        try add("Payload/App.app/PlugIns/Extension.appex/Info.plist", data: Data("not main metadata".utf8), method: .none)
        if noise > 0 { try add("Payload/App.app/Executable", data: Data(repeating: 65, count: noise), method: .none) }
        return try XCTUnwrap(archive.data)
    }

    private func lookup(_ data: Data, readBytes: ((Int) -> Void)? = nil) async throws -> VersionMetadata {
        try await RemoteIPAReader.metadata(size: Int64(data.count), bundleID: bundle) { range in
            readBytes?(range.count)
            return data.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
        }
    }

    func testXMLAndBinaryStoredAndDeflatedPlists() async throws {
        for binary in [false, true] {
            for method in [CompressionMethod.none, .deflate] {
                let metadata = try await lookup(fixture(binary: binary, compression: method))
                XCTAssertEqual(metadata.displayVersion, "1.2.3")
                XCTAssertEqual(metadata.releaseDate, date)
            }
        }
    }

    func testOnlyMainAppMetadataIsReadWithoutDownloadingExecutable() async throws {
        let ipa = try fixture(noise: 2 * 1024 * 1024)
        var bytes = 0
        let metadata = try await lookup(ipa) { bytes += $0 }
        XCTAssertEqual(metadata.displayVersion, "1.2.3")
        XCTAssertLessThan(bytes, 128 * 1024)
    }

    func testZIP64DirectoryAndCommentAreSupported() async throws {
        var ipa = try fixture()
        var end = Data(ipa.suffix(22))
        let directorySize = read32(end, 12), directoryOffset = read32(end, 16)
        let entries = UInt64(end[10]) | UInt64(end[11]) << 8
        ipa.removeLast(22)
        let recordOffset = UInt64(ipa.count)
        var record = Data()
        record.le(UInt32(0x06064b50)); record.le(UInt64(44)); record.le(UInt16(45)); record.le(UInt16(45))
        record.le(UInt32(0)); record.le(UInt32(0)); record.le(entries); record.le(entries)
        record.le(UInt64(directorySize)); record.le(UInt64(directoryOffset))
        record.le(UInt32(0x07064b50)); record.le(UInt32(0)); record.le(recordOffset); record.le(UInt32(1))
        for i in 8..<12 { end[i] = 0xff }
        for i in 12..<20 { end[i] = 0xff }
        end[20] = 3; end[21] = 0
        ipa.append(record); ipa.append(end); ipa.append(Data("zip".utf8))
        let metadata = try await lookup(ipa)
        XCTAssertEqual(metadata.displayVersion, "1.2.3")
    }

    func testDatePrecedenceLegacyKeysAndInvalidExplicitDate() throws {
        func plist(_ values: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) }
        var info: [String: Any] = ["CFBundleIdentifier": bundle, "bundleShortVersionString": " 2.0 ", "ReleaseDate": "2023-01-02"]
        var result = try RemoteIPAReader.parseInfo(plist(info), modified: date, bundleID: bundle)
        XCTAssertEqual(result.displayVersion, "2.0")
        XCTAssertEqual(result.releaseDate, VersionLookup.parseReleaseDate("2023-01-02"))
        info["releaseDate"] = 1_704_067_200
        result = try RemoteIPAReader.parseInfo(plist(info), modified: nil, bundleID: bundle)
        XCTAssertEqual(result.releaseDate, date)
        info["releaseDate"] = "invalid"
        XCTAssertThrowsError(try RemoteIPAReader.parseInfo(plist(info), modified: date, bundleID: bundle))
        info.removeValue(forKey: "releaseDate"); info.removeValue(forKey: "ReleaseDate")
        XCTAssertThrowsError(try RemoteIPAReader.parseInfo(plist(info), modified: nil, bundleID: bundle))
        XCTAssertThrowsError(try RemoteIPAReader.parseInfo(plist(info), modified: date, bundleID: "wrong.bundle"))
    }

    func testTruncatedArchiveAndCorruptCRCFail() async throws {
        let ipa = try fixture(compression: .none)
        do { _ = try await lookup(Data(ipa.dropLast(5))); XCTFail("Truncated ZIP accepted") } catch {}
        var corrupt = ipa
        let nameLength = Int(corrupt[26]) | Int(corrupt[27]) << 8
        let extraLength = Int(corrupt[28]) | Int(corrupt[29]) << 8
        corrupt[30 + nameLength + extraLength] ^= 1
        do { _ = try await lookup(corrupt); XCTFail("Corrupt CRC accepted") } catch {}
    }

    func testWrongBundleAndOversizedMetadataAreRejected() async throws {
        for info in [
            ["CFBundleIdentifier": "other.app", "CFBundleShortVersionString": "1.0"],
            ["CFBundleIdentifier": bundle, "CFBundleShortVersionString": "1.0", "padding": String(repeating: "x", count: RemoteIPAReader.metadataLimit + 1)]
        ] {
            let ipa = try fixture(info: info)
            do { _ = try await lookup(ipa); XCTFail("Invalid main metadata accepted") } catch {}
        }
    }

    func testStaleAPIValuesAreNeverUsedAndLicenseErrorsAreTyped() async throws {
        let app = Software(id: 42, bundleID: bundle, name: "History", version: "9.9", artistName: "", sellerName: "", description: "", averageUserRating: 0,
            userRatingCount: 0, artworkUrl: "", screenshotUrls: [], minimumOsVersion: "15", fileSizeBytes: "", releaseDate: "", primaryGenreName: "")
        let response: [String: Any] = ["songList": [["URL": "https://example.invalid/app.ipa", "metadata": ["itemId": "42", "softwareVersionExternalIdentifier": "99",
            "softwareVersionBundleId": bundle, "bundleShortVersionString": "STALE", "releaseDate": "1990-01-01"]]]]
        let expected = VersionMetadata(displayVersion: "1.2.3", releaseDate: date)
        let result = try await VersionLookup.metadata(from: response, app: app, versionID: "99") { _ in expected }
        XCTAssertEqual(result, expected)
        do {
            _ = try await VersionLookup.metadata(from: response, app: app, versionID: "99") { _ in throw RemoteIPAReader.Failure.invalidArchive }
            XCTFail("Silently fell back to stale API metadata")
        } catch {}
        do {
            _ = try await VersionLookup.metadata(from: ["failureType": "9610"], app: app, versionID: "99") { _ in XCTFail(); return expected }
            XCTFail("License error swallowed")
        } catch { guard case ApplePackageError.licenseRequired = error else { return XCTFail("Wrong error") } }
    }

    func testRangeResponseValidationAndServerIgnoringRange() async throws {
        XCTAssertNil(BoundedRangeRequest.contentRange("bytes 1-0/10"))
        XCTAssertNil(BoundedRangeRequest.contentRange("bytes 0-9/*"))
        XCTAssertNil(BoundedRangeRequest.contentRange("bytes 0-10/10"))
        XCTAssertEqual(BoundedRangeRequest.contentRange("bytes 0-0/100")?.total, 100)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeProtocol.self]
        for path in ["ignored", "wrong", "overflow"] {
            do {
                _ = try await BoundedRangeRequest.fetch(url: URL(string: "https://example.invalid/" + path)!, range: 0..<1, configuration: config)
                XCTFail("Accepted invalid range response")
            } catch {}
        }
        let response = try await BoundedRangeRequest.fetch(url: URL(string: "https://example.invalid/valid")!, range: 0..<1, configuration: config)
        XCTAssertEqual(response.data, Data([1])); XCTAssertEqual(response.total, 100)
    }

    private func read32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << (8 * $1) }
    }
}

private final class RangeProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "ignored" ? 200 : 206, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Range": path == "wrong" ? "bytes 1-1/100" : "bytes 0-0/100"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: path == "overflow" ? Data([1, 2]) : Data([1]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
