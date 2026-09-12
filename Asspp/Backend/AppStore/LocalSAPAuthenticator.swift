import ApplePackage
import Foundation

enum LocalSAPAuthenticator {
    private struct SignRequest: Encodable {
        let setup: String
        let certificate: String
        let device: String
        let version: UInt32
        let body: Data
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
        try await Authenticator.authenticate(email: email, password: password, code: code.filter { !$0.isWhitespace }, cookies: cookies) { body, bag, device in
            guard let setup = bag.sapSetup, let certificate = bag.sapCertificate, let version = bag.sapVersion,
                  trustedAppleURL(setup), trustedAppleURL(certificate) else {
                throw Failure(message: "Apple bag 缺少有效的本地 SAP 配置。")
            }
            let request = SignRequest(setup: setup, certificate: certificate, device: device, version: version, body: body)
            let data = try JSONEncoder().encode(request)
            let input = String(decoding: data, as: UTF8.self)
            // SAP emulation and setup networking are blocking: keep them off the UI actor.
            return try await Task.detached(priority: .userInitiated) {
                let result = input.withCString { AssppSAPSign($0) }
                guard let result else { throw Failure(message: "本地 SAP 未返回结果。") }
                defer { AssppSAPFree(result) }
                let output = try JSONDecoder().decode(SignResponse.self, from: Data(String(cString: result).utf8))
                if let error = output.error { throw Failure(message: error) }
                guard let signature = output.signature, !signature.isEmpty else { throw Failure(message: "本地 SAP 签名为空。") }
                return signature.base64EncodedString()
            }.value
        }
    }

    private static func trustedAppleURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(), url.user == nil else { return false }
        return host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com")
    }
}
