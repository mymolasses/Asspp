import ApplePackage
import Foundation

extension FeatureChecks {
    @MainActor
    static func checkHistoryLoading(package: AppStore.AppPackage) async throws -> Int {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func waitFor(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(5)
            while !condition() {
                precondition(Date() < deadline, "History request did not settle")
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        var lists = 0
        var requests: [String] = []
        var pending: [String: CheckedContinuation<VersionMetadata, Error>] = [:]
        let archive = AppPackageArchive(accountID: "fixture@example.com", region: "US", package: package,
            listVersions: { _, _ in
                lists += 1
                return ["100", "200", "200", "300"]
            }, loadVersion: { _, _, id in
                requests.append(id)
                return try await withCheckedThrowingContinuation { pending[id] = $0 }
            })
        archive.populateVersionIdentifiers()
        try await waitFor { !archive.loading }
        check(lists == 1 && archive.versionIdentifiers == ["300", "200", "100"], "List reverses and deduplicates IDs")
        check(requests.isEmpty && archive.versionItems.isEmpty, "Opening history never fetches metadata")
        check(archive.package(for: "300") == nil, "Unloaded ID does not display the latest version as historical metadata")

        archive.populateVersionItem(for: "300")
        archive.populateVersionItem(for: "300")
        archive.populateVersionItem(for: "200")
        archive.populateVersionItem(for: "unknown")
        try await waitFor { pending.count == 2 }
        check(requests.count == 2 && Set(requests) == ["300", "200"], "Only explicitly requested IDs load; duplicate taps do not duplicate requests")
        check(!archive.loading && archive.loadingVersionIDs == ["300", "200"], "Details have independent row loading states")
        let metadata = VersionMetadata(displayVersion: "1.2.3", releaseDate: Date(timeIntervalSince1970: 1_700_000_000))
        pending.removeValue(forKey: "300")!.resume(returning: metadata)
        pending.removeValue(forKey: "200")!.resume(throwing: NSError(domain: "fixture", code: 1))
        try await waitFor { archive.loadingVersionIDs.isEmpty }
        check(archive.versionItems["300"] == metadata && archive.versionItems["200"] == nil, "Details apply only to their ID")
        check(archive.versionErrors["200"] != nil && archive.error == nil, "Detail errors stay in their row")
        let historical = archive.package(for: "300")
        check(historical?.externalVersionID == "300" && historical?.software.version == "1.2.3" && historical?.releaseDate == metadata.releaseDate,
              "Historical download uses the requested ID, version and date")
        archive.populateVersionItem(for: "300")
        check(requests.count == 2, "Loaded metadata is reused")

        archive.populateVersionItem(for: "200")
        try await waitFor { pending["200"] != nil }
        check(archive.versionErrors["200"] == nil, "Retry clears the row error")
        pending.removeValue(forKey: "200")!.resume(returning: metadata)
        try await waitFor { archive.loadingVersionIDs.isEmpty }
        check(archive.versionItems["200"] == metadata, "A failed detail request can be retried")

        archive.populateVersionItem(for: "100")
        try await waitFor { pending["100"] != nil }
        let staleRequest = pending.removeValue(forKey: "100")!
        archive.populateVersionIdentifiers()
        try await waitFor { !archive.loading }
        check(lists == 2 && archive.versionItems.isEmpty && archive.loadingVersionIDs.isEmpty, "Refresh reloads only the ID list")
        archive.populateVersionItem(for: "100")
        try await waitFor { pending["100"] != nil }
        staleRequest.resume(returning: metadata)
        // Drain the stale task before completing its replacement.
        try await Task.sleep(nanoseconds: 20_000_000)
        check(archive.versionItems["100"] == nil && archive.loadingVersionIDs.contains("100"), "Stale details cannot overwrite refreshed rows")
        pending.removeValue(forKey: "100")!.resume(returning: metadata)
        try await waitFor { archive.loadingVersionIDs.isEmpty }
        check(archive.versionItems["100"] == metadata, "The refreshed row receives its own result")
        return checks
    }
}
