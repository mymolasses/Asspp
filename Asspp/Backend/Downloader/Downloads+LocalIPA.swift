import ApplePackage
import Foundation

extension Downloads {
    func importLocalIPA(from url: URL, displayName: String) async throws -> PackageManifest {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("ipa")
        defer { try? FileManager.default.removeItem(at: staging) }
        let info = try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "ipa" else { throw LocalIPAReader.Failure.invalidIPA }
            // Copy on a worker, then inspect that exact snapshot. The source can
            // be an iCloud document and must stay security-scoped until copied.
            try FileManager.default.copyItem(at: url, to: staging)
            return try LocalIPAReader.read(staging, originalFileName: url.lastPathComponent)
        }.value
        try Task.checkCancellation()
        let manifest = PackageManifest(localIPA: info, displayName: displayName)
        let target = manifest.targetLocation
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: target)
        }.value
        // Local imports keep their existing signature and bytes unchanged.
        return add(request: manifest)
    }

    func renameLocalIPA(_ manifest: PackageManifest, to name: String) {
        guard manifest.isLocal else { return }
        manifest.displayName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        objectWillChange.send()
        saveManifests()
    }

    func refreshLocalIPAInfo(_ manifest: PackageManifest) async throws {
        guard let original = manifest.localIPA else { return }
        let url = manifest.targetLocation
        let info = try await Task.detached(priority: .userInitiated) {
            try LocalIPAReader.read(url, originalFileName: original.originalFileName)
        }.value
        guard info.bundleID == original.bundleID else { throw LocalIPAReader.Failure.invalidMetadata }
        manifest.updateLocalIPAInfo(info)
        saveManifests()
    }
}
