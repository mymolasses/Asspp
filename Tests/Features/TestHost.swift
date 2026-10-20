// Minimal in-memory hosts for production feature extensions. Tests never use
// the app singleton, the user's Keychain, Digger, or any Apple network API.
import Combine
import Foundation

@MainActor
class AppStore {
    static let this = AppStore()
    nonisolated func withAccount<T>(id: String, _ body: (inout UserAccount) async throws -> T) async throws -> T {
        throw NSError(domain: "FeatureChecks.UnexpectedNetworkAccess", code: 1)
    }
    var accounts: [UserAccount] = []
    var verifiedAccountIDs: Set<String> = []
    var sessionErrors: [String: String] = [:]
    var refreshingAccountIDs: Set<String> = []
}

@MainActor
class Downloads: ObservableObject {
    var manifests: [PackageManifest] = []
    var saveCount = 0
    func add(request: PackageManifest) -> PackageManifest {
        manifests.append(request)
        return request
    }
    func saveManifests() { saveCount += 1 }
}

let documentsDirectory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("isolated-package-storage")
