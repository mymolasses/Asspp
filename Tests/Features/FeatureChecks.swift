import ApplePackage
import Foundation

@main
struct FeatureChecks {
    @MainActor
    static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let password = "test-密码🔑"
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func rejects(_ message: String, _ operation: () throws -> Void) {
            do { try operation() }
            catch { checks += 1; return }
            fatalError(message)
        }
        let web = try Data(contentsOf: fixtures.appendingPathComponent("web.enc"))
        check(try AccountBackupCrypto.readFile(fixtures.appendingPathComponent("web.enc")) == web, "Bounded file read")
        let decoded = try AccountTransfer.decode(web, password: password)
        check(decoded.count == 1, "Web backup account count")
        let user = decoded[0]
        check(user.id == "fixture@example.com", "Web email")
        check(user.deviceIdentifier == "AABBCCDDEEFF", "Per-account GUID preserved")
        check(user.account.cookie.first?.expiresAt == 2_100_000_000, "Cookie timestamps use seconds")
        check(user.account.cookie.first?.secure == true, "Secure cookie flag")
        check(user.account.pod == "25", "Pod preserved")
        let legacy = try AccountTransfer.decode(Data(contentsOf: fixtures.appendingPathComponent("legacy.enc")), password: password)
        check(legacy[0].account == user.account, "Legacy array backup")
        check(legacy[0].deviceIdentifier == user.deviceIdentifier, "Legacy GUID")
        let exported = try AccountTransfer.export(accounts: [.init(user, fallbackDeviceIdentifier: "001122334455")], password: password)
        try exported.write(to: fixtures.appendingPathComponent("native.enc"))
        check(exported != web, "Random salt and nonce")
        check(try AccountTransfer.decode(exported, password: password)[0].account == user.account, "Native round trip")
        rejects("Wrong password must fail") { _ = try AccountTransfer.decode(web, password: "wrong") }
        rejects("Empty password must fail") { _ = try AccountTransfer.decode(web, password: "") }
        rejects("Invalid Base64 must fail") { _ = try AccountTransfer.decode(Data("not-base64".utf8), password: password) }
        var bytes = Data(base64Encoded: String(decoding: web, as: UTF8.self))!
        bytes[bytes.count - 1] ^= 1
        rejects("Tampered GCM tag must fail") {
            _ = try AccountTransfer.decode(Data(bytes.base64EncodedString().utf8), password: password)
        }
        let oversizedFile = Data(repeating: 65, count: AccountBackupCrypto.maximumFileSize + 1)
        rejects("Oversized backup must fail") { _ = try AccountBackupCrypto.decrypt(oversizedFile, password: password) }
        let oversizedURL = fixtures.appendingPathComponent("oversized.enc")
        try oversizedFile.write(to: oversizedURL)
        rejects("Oversized file read must stop at limit") { _ = try AccountBackupCrypto.readFile(oversizedURL) }
        let version = try AccountBackupCrypto.encrypt(Data("{\"format\":\"asspp.accounts\",\"version\":99,\"accounts\":[]}".utf8), password: password)
        rejects("Unknown backup version must fail") { _ = try AccountTransfer.decode(version, password: password) }
        var invalidAccount = AccountTransfer.WebAccount(user, fallbackDeviceIdentifier: "001122334455")
        invalidAccount.deviceIdentifier = "../not-a-guid"
        rejects("Invalid GUID must fail validation") { _ = try invalidAccount.userAccount() }
        invalidAccount.deviceIdentifier = "001122334455"
        invalidAccount.store = "unsupported-store"
        rejects("Unsupported storefront must fail validation") { _ = try invalidAccount.userAccount() }
        var oldUserJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(user)) as! [String: Any]
        oldUserJSON.removeValue(forKey: "deviceIdentifier")
        let oldUser = try JSONDecoder().decode(AppStore.UserAccount.self, from: JSONSerialization.data(withJSONObject: oldUserJSON))
        check(oldUser.deviceIdentifier == nil, "Existing Keychain records remain decodable")
        check(AccountTransfer.WebAccount(oldUser, fallbackDeviceIdentifier: "001122334455").deviceIdentifier == "001122334455", "Legacy export GUID")

        let store = AppStore()
        store.accounts = [user]
        var replacement = user
        replacement.account.passwordToken = "new-fixture-token"
        replacement.account.email = "FIXTURE@example.com"
        store.verifiedAccountIDs.insert(user.id)
        check(store.importAccounts([replacement], overwrite: false) == 0, "Keep case-insensitive conflict")
        check(store.accounts[0].account.passwordToken == "fixture-only-token", "Keep existing preserves credentials")
        check(store.importAccounts([replacement], overwrite: true) == 1, "Replace conflict")
        check(store.accounts.count == 1, "Replacement does not duplicate account")
        check(!store.verifiedAccountIDs.contains(user.id), "Imported sessions are unverified")
        store.refreshingAccountIDs.insert(replacement.id)
        check(store.importAccounts([user], overwrite: true) == 0, "Refresh cannot be overwritten")

        ApplePackage.Configuration.deviceIdentifier = "001122334455"
        try await withThrowingTaskGroup(of: String.self) { group in
            for guid in ["AABBCCDDEEFF", "FFEEDDCCBBAA"] {
                group.addTask {
                    try await ApplePackage.Configuration.$accountDeviceIdentifier.withValue(guid) {
                        try await Task.sleep(nanoseconds: 10_000_000)
                        return ApplePackage.Configuration.deviceIdentifier
                    }
                }
            }
            var observed: Set<String> = []
            for try await guid in group { observed.insert(guid) }
            check(observed == ["AABBCCDDEEFF", "FFEEDDCCBBAA"], "Concurrent GUID isolation")
        }
        check(ApplePackage.Configuration.deviceIdentifier == "001122334455", "Default GUID restored")

        let valid = fixtures.appendingPathComponent("valid.ipa")
        let info = try LocalIPAReader.read(valid, originalFileName: "valid.ipa")
        check(info.bundleID == "com.example.fixture", "IPA bundle ID")
        check(info.version == "1.2.3" && info.buildVersion == "42", "IPA version and build")
        check(info.signing.profileType == .enterprise && info.signing.expired, "CMS metadata and expiry")
        check(info.signing.hasCodeResources, "CodeResources")
        check(info.signing.matches(bundleID: info.bundleID), "Profile bundle ID")
        check(!info.signing.matches(bundleID: "com.other.fixture"), "Profile mismatch")
        var wildcard = info.signing
        wildcard.applicationIdentifier = "TESTTEAM.com.example.*"
        check(wildcard.matches(bundleID: info.bundleID), "Wildcard profile")
        check(!wildcard.matches(bundleID: "com.exampleevil.fixture"), "Wildcard boundary")
        let binary = try LocalIPAReader.read(fixtures.appendingPathComponent("binary.ipa"), originalFileName: "binary.ipa")
        check(binary.name == info.name && binary.signing.profileType == .missing, "Binary plist and missing profile")
        for name in ["ambiguous.ipa", "invalid-id.ipa", "oversize.ipa", "oversize-profile.ipa", "bad-crc.ipa", "nested-only.ipa", "broken.ipa", "wrong.txt"] {
            rejects("Invalid IPA should fail: \(name)") {
                _ = try LocalIPAReader.read(fixtures.appendingPathComponent(name), originalFileName: name)
            }
        }
        let downloads = Downloads()
        let imported = try await downloads.importLocalIPA(from: valid, displayName: "  My Local App  ")
        check(imported.completed && imported.account == nil, "Import without account")
        check(imported.displayPackage.software.name == "My Local App", "Custom display name")
        check(imported.package.software.name == "Fixture App", "Original metadata preserved")
        check(imported.installationBundleVersion == "42" && imported.package.software.version == "1.2.3", "Installation uses build version while display uses marketing version")
        check(try Data(contentsOf: imported.targetLocation) == Data(contentsOf: valid), "IPA bytes preserved")
        let repeated = try await downloads.importLocalIPA(from: valid, displayName: "")
        check(imported.targetLocation != repeated.targetLocation, "Imports do not overwrite files")
        downloads.renameLocalIPA(imported, to: String(repeating: "A", count: 130))
        check(imported.displayName.count == 120 && downloads.saveCount == 1, "Rename capped and persisted")
        downloads.renameLocalIPA(imported, to: "  ")
        check(imported.displayPackage.software.name == "Fixture App", "Empty name restores original")
        try await downloads.refreshLocalIPAInfo(imported)
        check(imported.localIPA?.signing.profileName == "Fixture Profile" && downloads.saveCount == 3, "Refresh signing metadata")
        let nameless = try await downloads.importLocalIPA(from: fixtures.appendingPathComponent("nameless.ipa"), displayName: "")
        check(nameless.package.software.name == "nameless", "Missing name falls back to original file name")
        let unsafe = try await downloads.importLocalIPA(from: fixtures.appendingPathComponent("unsafe-version.ipa"), displayName: "")
        check(unsafe.targetLocation.deletingLastPathComponent().lastPathComponent == "Local", "Metadata cannot escape storage")
        check(unsafe.targetLocation.lastPathComponent == "\(unsafe.id.uuidString).ipa", "Local path uses UUID")
        let restored = try JSONDecoder().decode(PackageManifest.self, from: JSONEncoder().encode(imported))
        check(restored.id == imported.id && restored.completed && restored.isLocal, "Local manifest reload")
        check(restored.targetLocation == imported.targetLocation, "Imported path survives reload")
        let output = ApplePackage.DownloadOutput(downloadURL: "https://example.com/fixture.ipa", sinfs: [],
            bundleShortVersionString: "1.2.3", bundleVersion: "42", iTunesMetadata: Data())
        let remote = try PackageManifest(account: user, package: imported.package, downloadOutput: output)
        let remoteData = try JSONEncoder().encode(remote)
        let remoteString = String(decoding: remoteData, as: UTF8.self)
        check(!remoteString.contains("fixture-only-password") && !remoteString.contains("passwordToken") && !remoteString.contains("fixture-cookie"), "Download records exclude secrets")
        var oldManifestJSON = try JSONSerialization.jsonObject(with: remoteData) as! [String: Any]
        oldManifestJSON["account"] = oldUserJSON
        oldManifestJSON.removeValue(forKey: "localIPA")
        oldManifestJSON.removeValue(forKey: "displayName")
        let oldManifest = try JSONDecoder().decode(PackageManifest.self, from: JSONSerialization.data(withJSONObject: oldManifestJSON))
        check(oldManifest.account?.id == user.id && !oldManifest.isLocal, "Legacy download migration")
        let migrated = String(decoding: try JSONEncoder().encode(oldManifest), as: UTF8.self)
        check(!migrated.contains("passwordToken") && !migrated.contains("fixture-only-password"), "Migration strips secrets")
        imported.delete()
        check(!FileManager.default.fileExists(atPath: imported.targetLocation.path), "Delete imported copy")
        check(FileManager.default.fileExists(atPath: valid.path), "Source IPA remains intact")
        print("PASS: \(checks) backup, account migration, GUID isolation, IPA and persistence checks")
    }
}
