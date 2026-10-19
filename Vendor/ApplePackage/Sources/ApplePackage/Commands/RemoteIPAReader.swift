import Foundation
import CoreFoundation
import ZIPFoundation

/// Fetch only the ZIP index and the main app's Info.plist, never the whole IPA.
enum RemoteIPAReader {
    static let metadataLimit = 2 * 1024 * 1024
    static let directoryLimit = 8 * 1024 * 1024
    typealias Read = (Range<Int64>) async throws -> Data

    enum Failure: LocalizedError {
        case invalidArchive, unsupportedRange, oversizedMetadata, mismatchedApp
        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "无法读取 IPA 内的历史版本信息：ZIP 或 Info.plist 无效。"
            case .unsupportedRange: return "安装包服务器不支持有效的分段读取，无法查询真实版本信息。"
            case .oversizedMetadata: return "IPA 目录或信息文件超过读取上限。"
            case .mismatchedApp: return "IPA 内的应用标识与请求的 App 不匹配。"
            }
        }
    }

    struct Entry {
        var name: Data
        var offset: UInt64
        var compressed: UInt64
        var uncompressed: UInt64
        var method: UInt16
        var flags: UInt16
        var checksum: UInt32
        var time: UInt16
        var date: UInt16
        var modified: Date?
    }

    static func metadata(url: URL, bundleID: String) async throws -> VersionMetadata {
        let first = try await BoundedRangeRequest.fetch(url: url, range: 0..<1)
        let size = first.total
        return try await metadata(size: size, bundleID: bundleID) { range in
            let result = try await BoundedRangeRequest.fetch(url: url, range: range)
            guard result.total == size else { throw Failure.invalidArchive }
            return result.data
        }
    }

    static func metadata(size: Int64, bundleID: String, read: Read) async throws -> VersionMetadata {
        guard size >= 22 else { throw Failure.invalidArchive }
        func fetch(_ offset: UInt64, _ count: UInt64) async throws -> Data {
            try Task.checkCancellation()
            guard offset <= UInt64(size), count > 0, count <= UInt64(directoryLimit),
                  count <= UInt64(size) - offset else { throw Failure.invalidArchive }
            let data = try await read(Int64(offset)..<Int64(offset + count))
            guard data.count == Int(count) else { throw Failure.invalidArchive }
            return data
        }
        let tailStart = max(0, size - 65_557 - 20)
        let tail = try await fetch(UInt64(tailStart), UInt64(size - tailStart))
        guard let end = try (0...(tail.count - 22)).reversed().first(where: {
            try tail.uint32($0) == 0x06054b50 && $0 + 22 + Int(tail.uint16($0 + 20)) == tail.count
        }), try tail.uint16(end + 4) == 0, try tail.uint16(end + 6) == 0 else { throw Failure.invalidArchive }
        var count = UInt64(try tail.uint16(end + 10))
        var length = UInt64(try tail.uint32(end + 12))
        var offset = UInt64(try tail.uint32(end + 16))
        guard try tail.uint16(end + 8) == tail.uint16(end + 10) else { throw Failure.invalidArchive }
        if count == 0xffff || length == 0xffffffff || offset == 0xffffffff {
            guard end >= 20, try tail.uint32(end - 20) == 0x07064b50,
                  try tail.uint32(end - 16) == 0, try tail.uint32(end - 4) == 1 else { throw Failure.invalidArchive }
            let zip64 = try await fetch(tail.uint64(end - 12), 56)
            guard try zip64.uint32(0) == 0x06064b50, try zip64.uint64(4) >= 44,
                  try zip64.uint32(16) == 0, try zip64.uint32(20) == 0,
                  try zip64.uint64(24) == zip64.uint64(32) else { throw Failure.invalidArchive }
            count = try zip64.uint64(32)
            length = try zip64.uint64(40)
            offset = try zip64.uint64(48)
        }
        guard length <= UInt64(directoryLimit), count > 0, count <= 100_000 else { throw Failure.oversizedMetadata }
        guard offset <= UInt64(tailStart + Int64(end)), length <= UInt64(tailStart + Int64(end)) - offset else { throw Failure.invalidArchive }
        let directory = try await fetch(offset, length)
        let entry = try mainEntry(directory, count: count)
        guard entry.offset < offset, entry.compressed > 0,
              entry.compressed <= UInt64(metadataLimit), entry.uncompressed <= UInt64(metadataLimit) else { throw Failure.oversizedMetadata }
        let local = try await fetch(entry.offset, 30)
        guard try local.uint32(0) == 0x04034b50, try local.uint16(8) == entry.method,
              try local.uint16(6) == entry.flags else { throw Failure.invalidArchive }
        let variableSize = UInt64(try local.uint16(26)) + UInt64(try local.uint16(28))
        let variable = try await fetch(entry.offset + 30, variableSize)
        guard variable.prefix(Int(try local.uint16(26))) == entry.name else { throw Failure.invalidArchive }
        let dataOffset = entry.offset + 30 + variableSize
        guard dataOffset <= offset, entry.compressed <= offset - dataOffset else { throw Failure.invalidArchive }
        let compressed = try await fetch(dataOffset, entry.compressed)
        let plist = try unpack(compressed, entry: entry)
        return try parseInfo(plist, modified: entry.modified, bundleID: bundleID)
    }

    static func mainEntry(_ directory: Data, count: UInt64) throws -> Entry {
        var cursor = 0
        var found: Entry?
        for _ in 0..<count {
            guard try directory.uint32(cursor) == 0x02014b50 else { throw Failure.invalidArchive }
            let nameSize = Int(try directory.uint16(cursor + 28))
            let extraSize = Int(try directory.uint16(cursor + 30))
            let commentSize = Int(try directory.uint16(cursor + 32))
            let end = cursor + 46 + nameSize + extraSize + commentSize
            guard end <= directory.count else { throw Failure.invalidArchive }
            let name = directory.subdata(in: cursor + 46 ..< cursor + 46 + nameSize)
            let path = String(data: name, encoding: .utf8) ?? String(data: name, encoding: .isoLatin1) ?? ""
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 3, parts[0] == "Payload", parts[1].hasSuffix(".app"), parts[2] == "Info.plist" {
                guard found == nil else { throw Failure.invalidArchive }
                var entry = Entry(name: name, offset: UInt64(try directory.uint32(cursor + 42)),
                    compressed: UInt64(try directory.uint32(cursor + 20)), uncompressed: UInt64(try directory.uint32(cursor + 24)),
                    method: try directory.uint16(cursor + 10), flags: try directory.uint16(cursor + 8),
                    checksum: try directory.uint32(cursor + 16), time: try directory.uint16(cursor + 12),
                    date: try directory.uint16(cursor + 14), modified: nil)
                guard entry.flags & 1 == 0, [0, 8].contains(entry.method), try directory.uint16(cursor + 34) == 0 else { throw Failure.invalidArchive }
                let extra = directory.subdata(in: cursor + 46 + nameSize ..< cursor + 46 + nameSize + extraSize)
                try readExtra(extra, entry: &entry)
                guard entry.offset != 0xffffffff, entry.compressed != 0xffffffff, entry.uncompressed != 0xffffffff else { throw Failure.invalidArchive }
                if entry.modified == nil { entry.modified = dosDate(date: entry.date, time: entry.time) }
                found = entry
            }
            cursor = end
        }
        guard cursor == directory.count, let entry = found else { throw Failure.invalidArchive }
        return entry
    }

    private static func readExtra(_ data: Data, entry: inout Entry) throws {
        var cursor = 0
        while cursor < data.count {
            let tag = try data.uint16(cursor)
            let size = Int(try data.uint16(cursor + 2))
            let start = cursor + 4
            guard size <= data.count - start else { throw Failure.invalidArchive }
            let field = data.subdata(in: start..<start + size)
            if tag == 1 {
                var position = 0
                if entry.uncompressed == 0xffffffff { entry.uncompressed = try field.uint64(position); position += 8 }
                if entry.compressed == 0xffffffff { entry.compressed = try field.uint64(position); position += 8 }
                if entry.offset == 0xffffffff { entry.offset = try field.uint64(position) }
            } else if tag == 0x5455, size >= 5, field[0] & 1 != 0 {
                entry.modified = Date(timeIntervalSince1970: TimeInterval(try field.uint32(1)))
            } else if tag == 0x000a, size >= 32, try field.uint16(4) == 1, try field.uint16(6) >= 24 {
                let ticks = try field.uint64(8)
                entry.modified = Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
            }
            cursor = start + size
        }
    }

    private static func dosDate(date: UInt16, time: UInt16) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: 1980 + Int(date >> 9), month: Int((date >> 5) & 15), day: Int(date & 31),
            hour: Int(time >> 11), minute: Int((time >> 5) & 63), second: Int(time & 31) * 2)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    private static func unpack(_ compressed: Data, entry: Entry) throws -> Data {
        // Repackage just the compressed plist as a small ordinary ZIP. ZIPFoundation
        // handles deflate and CRC; the source IPA may have ZIP64 offsets or descriptors.
        var local = Data()
        local.appendLE(UInt32(0x04034b50)); local.appendLE(UInt16(20)); local.appendLE(UInt16(0x800))
        local.appendLE(entry.method); local.appendLE(entry.time); local.appendLE(entry.date)
        local.appendLE(entry.checksum); local.appendLE(UInt32(compressed.count)); local.appendLE(UInt32(entry.uncompressed))
        local.appendLE(UInt16(entry.name.count)); local.appendLE(UInt16(0)); local.append(entry.name); local.append(compressed)
        var directory = Data()
        directory.appendLE(UInt32(0x02014b50)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(0x800))
        directory.appendLE(entry.method); directory.appendLE(entry.time); directory.appendLE(entry.date)
        directory.appendLE(entry.checksum); directory.appendLE(UInt32(compressed.count)); directory.appendLE(UInt32(entry.uncompressed))
        directory.appendLE(UInt16(entry.name.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0)); directory.appendLE(UInt32(0)); directory.appendLE(UInt32(0)); directory.append(entry.name)
        var end = Data()
        end.appendLE(UInt32(0x06054b50)); end.appendLE(UInt16(0)); end.appendLE(UInt16(0)); end.appendLE(UInt16(1)); end.appendLE(UInt16(1))
        end.appendLE(UInt32(directory.count)); end.appendLE(UInt32(local.count)); end.appendLE(UInt16(0))
        let archive = try Archive(data: local + directory + end, accessMode: .read)
        guard let file = archive.first, file.type == .file else { throw Failure.invalidArchive }
        var output = Data()
        let crc = try archive.extract(file) { chunk in
            try Task.checkCancellation()
            guard chunk.count <= metadataLimit - output.count else { throw Failure.oversizedMetadata }
            output.append(chunk)
        }
        guard crc == entry.checksum, output.count == Int(entry.uncompressed) else { throw Failure.invalidArchive }
        return output
    }

    static func parseInfo(_ data: Data, modified: Date?, bundleID: String) throws -> VersionMetadata {
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw Failure.invalidArchive }
        guard !bundleID.isEmpty, info["CFBundleIdentifier"] as? String == bundleID else { throw Failure.mismatchedApp }
        if let platforms = info["CFBundleSupportedPlatforms"] as? [String], !platforms.contains("iPhoneOS") { throw Failure.mismatchedApp }
        let rawVersion = info["CFBundleShortVersionString"] ?? info["bundleShortVersionString"]
        let version: String
        if let value = rawVersion as? String { version = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        else if let value = rawVersion as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { version = value.stringValue }
        else { throw Failure.invalidArchive }
        guard !version.isEmpty else { throw Failure.invalidArchive }
        let date: Date?
        if let explicit = info["releaseDate"] ?? info["ReleaseDate"] {
            date = VersionLookup.parseReleaseDate(explicit)
        } else { date = modified }
        guard let date else { throw Failure.invalidArchive }
        return VersionMetadata(displayVersion: version, releaseDate: date)
    }
}

private extension Data {
    func uint16(_ offset: Int) throws -> UInt16 { UInt16(try integer(offset, bytes: 2)) }
    func uint32(_ offset: Int) throws -> UInt32 { UInt32(try integer(offset, bytes: 4)) }
    func uint64(_ offset: Int) throws -> UInt64 { try integer(offset, bytes: 8) }
    func integer(_ offset: Int, bytes: Int) throws -> UInt64 {
        guard offset >= 0, offset <= count, bytes <= count - offset else { throw RemoteIPAReader.Failure.invalidArchive }
        return (0..<bytes).reduce(UInt64(0)) { $0 | UInt64(self[offset + $1]) << (8 * $1) }
    }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
