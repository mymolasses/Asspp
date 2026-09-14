import ApplePackage
import Foundation

enum LocalSAPAuthenticator {
    // Challenge cookies are memory-only, account-scoped and short lived.
    private actor Challenges {
        private var values: [String: (Date, [Cookie])] = [:]
        func take(_ key: String) -> [Cookie]? {
            guard let value = values.removeValue(forKey: key), Date().timeIntervalSince(value.0) < 300 else { return nil }
            return value.1
        }
        func save(_ cookies: [Cookie], for key: String) {
            values = values.filter { Date().timeIntervalSince($0.value.0) < 300 }
            values[key] = (Date(), cookies)
        }
    }
    private static let challenges = Challenges()
    private static let signingQueue = DispatchQueue(label: "wiki.qaq.Asspp.localSAP", qos: .userInitiated)
    private struct SignRequest: Encodable {
        let setup: String
        let certificate: String
        let device: String
        let version: UInt32
        let body: Data
        let session: String
        let cacheDirectory: String
    }
    private struct SignResponse: Decodable {
        let signature: Data?
        let error: String?
    }
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func authenticate(email: String, password: String, code: String, cookies: [Cookie]) async throws -> Account {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + ":" + Configuration.deviceIdentifier
        let previousChallenge = await challenges.take(key)
        let normalizedCode = code.filter { !$0.isWhitespace }
        let loginCookies = normalizedCode.isEmpty ? cookies : (previousChallenge ?? cookies)
        // Resolve this for each login: LiveContainer can relocate the sandbox
        // and does not necessarily export HOME to the embedded Go runtime.
        let cacheDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            .appendingPathComponent("AssppSAP", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let session = UUID().uuidString
        defer {
            // Destroy the signer off the main actor, on the same queue as signing.
            signingQueue.async {
                let input = "{\"session\":\"\(session)\",\"close\":true}"
                if let result = input.withCString({ AssppSAPSign($0) }) { AssppSAPFree(result) }
            }
        }
        return try await Authenticator.authenticate(email: email, password: password, code: normalizedCode, cookies: loginCookies,
            onVerificationRequired: { cookies in await challenges.save(cookies, for: key) }) { body, bag, device in
            guard let setup = bag.sapSetup, let certificate = bag.sapCertificate, let version = bag.sapVersion,
                  trustedAppleURL(setup), trustedAppleURL(certificate) else {
                throw Failure(message: "Apple bag 缺少有效的本地 SAP 配置。")
            }
            let request = SignRequest(setup: setup, certificate: certificate, device: device, version: version,
                                      body: body, session: session, cacheDirectory: cacheDirectory.path)
            let data = try JSONEncoder().encode(request)
            let input = String(decoding: data, as: UTF8.self)
            // SAP emulation and setup networking are blocking: keep them off the UI actor.
            return try await withCheckedThrowingContinuation { continuation in
                signingQueue.async {
                    do {
                let result = input.withCString { AssppSAPSign($0) }
                guard let result else { throw Failure(message: "本地 SAP 未返回结果。") }
                defer { AssppSAPFree(result) }
                let output: SignResponse
                do {
                    output = try JSONDecoder().decode(SignResponse.self, from: Data(String(cString: result).utf8))
                } catch {
                    throw Failure(message: "本地 SAP 签名结果格式异常（JSON / Base64 解码失败），尚未向 Apple 发送本次登录请求。")
                }
                if let error = output.error { throw Failure(message: error) }
                guard let signature = output.signature, !signature.isEmpty else { throw Failure(message: "本地 SAP 签名为空。") }
                        continuation.resume(returning: signature.base64EncodedString())
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private static func trustedAppleURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(), url.user == nil else { return false }
        return host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com")
    }
}
