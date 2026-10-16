import CommonCrypto
import CryptoKit
import Foundation
import Security

// AssppWeb wire format: Base64(salt[16] + nonce[12] + ciphertext + tag[16]).
// PBKDF2-HMAC-SHA256, 100,000 rounds, AES-256-GCM.
enum AccountBackupCrypto {
    static let maximumFileSize = 16 * 1024 * 1024

    static func readFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(64 * 1024, maximumFileSize + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumFileSize else { throw Failure.invalidBackup }
        }
        return data
    }

    enum Failure: LocalizedError {
        case emptyPassword, invalidBackup, decryptionFailed, randomFailed

        var errorDescription: String? {
            switch self {
            case .emptyPassword: String(localized: "Enter a backup password.")
            case .invalidBackup: String(localized: "Invalid or unsupported account backup.")
            case .decryptionFailed: String(localized: "Incorrect password or damaged backup.")
            case .randomFailed: String(localized: "Unable to generate a secure backup key.")
            }
        }
    }

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw Failure.emptyPassword }
        let salt = try randomBytes(count: 16)
        let nonce = try AES.GCM.Nonce(data: randomBytes(count: 12))
        let sealed = try AES.GCM.seal(plaintext, using: key(password: password, salt: salt), nonce: nonce)
        let combined = salt + Data(nonce) + sealed.ciphertext + sealed.tag
        let file = Data(combined.base64EncodedString().utf8)
        guard file.count <= maximumFileSize else { throw Failure.invalidBackup }
        return file
    }

    static func decrypt(_ file: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw Failure.emptyPassword }
        guard file.count <= maximumFileSize,
              let string = String(data: file, encoding: .utf8),
              let combined = Data(base64Encoded: string.filter { !$0.isWhitespace }),
              combined.count > 44 else { throw Failure.invalidBackup }
        do {
            let salt = Data(combined.prefix(16))
            let box = try AES.GCM.SealedBox(combined: Data(combined.dropFirst(16)))
            return try AES.GCM.open(box, using: key(password: password, salt: salt))
        } catch {
            throw Failure.decryptionFailed
        }
    }

    private static func key(password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress!.assumingMemoryBound(to: Int8.self), passwordBuffer.count,
                    saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), saltBuffer.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000, &derived, derived.count)
            }
        }
        guard status == kCCSuccess else { throw Failure.invalidBackup }
        return SymmetricKey(data: derived)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw Failure.randomFailed
        }
        return Data(bytes)
    }
}
