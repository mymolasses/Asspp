//
//  RemoteSAPAuthenticator.swift
//  Asspp
//
//  Performs only the SAP part of Apple authentication remotely. All account
//  state returned by the service is converted to ApplePackage.Account and is
//  then used by the existing local lookup/download implementation.
//

import ApplePackage
import Foundation
import KeychainAccess

enum RemoteSAPAuthenticationError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(String, codeRequired: Bool)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AssppWeb authentication URL is not configured"
        case .invalidResponse:
            return "AssppWeb returned an invalid Apple account response"
        case let .server(message, _):
            return message
        }
    }

    var codeRequired: Bool {
        if case let .server(_, codeRequired) = self { return codeRequired }
        return false
    }
}

enum RemoteSAPAuthenticator {
    static let tokenKeychain = Keychain(service: "wiki.qaq.Asspp.RemoteSAP")

    static func validURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil,
              url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
    /// Set this in UserDefaults (key: AssppWebBaseURL), or in Info.plist
    /// (ASSPP_WEB_BASE_URL). The value must be an HTTPS URL.
    static var baseURL: URL? {
        let value = UserDefaults.standard.string(forKey: "AssppWebBaseURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "ASSPP_WEB_BASE_URL") as? String
        guard let value, let url = validURL(value) else {
            return nil
        }
        return url
    }

    private static var accessToken: String? {
        let value = (try? tokenKeychain.get("accessToken")) ?? UserDefaults.standard.string(forKey: "AssppWebAccessToken")
            ?? Bundle.main.object(forInfoDictionaryKey: "ASSPP_WEB_ACCESS_TOKEN") as? String
        return value?.isEmpty == false ? value : nil
    }

    private struct Request: Encodable {
        let email: String
        let password: String
        let authCode: String?
        let deviceId: String
        let existingCookies: [Cookie]
    }

    private struct Failure: Decodable {
        let error: String?
        let codeRequired: Bool?
    }

    private struct ResponseAccount: Decodable {
        let appleId: String
        let store: String
        let firstName: String
        let lastName: String
        let passwordToken: String
        let directoryServicesIdentifier: String
        let cookies: [Cookie]?
        let pod: String?
    }

    static func authenticate(
        email: String,
        password: String,
        code: String,
        cookies: [Cookie]
    ) async throws -> Account {
        guard let baseURL else { throw RemoteSAPAuthenticationError.notConfigured }
        let endpoint = baseURL.appendingPathComponent("api/apple/authenticate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Asspp/4.2", forHTTPHeaderField: "User-Agent")
        if let accessToken { request.setValue(accessToken, forHTTPHeaderField: "X-Access-Token") }
        request.httpBody = try JSONEncoder().encode(Request(
            email: email,
            password: password,
            authCode: code.isEmpty ? nil : code.replacingOccurrences(of: " ", with: ""),
            deviceId: Configuration.deviceIdentifier.lowercased(),
            existingCookies: cookies
        ))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 180
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteSAPAuthenticationError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let failure = (try? JSONDecoder().decode(Failure.self, from: data))
            throw RemoteSAPAuthenticationError.server(
                failure?.error ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                codeRequired: failure?.codeRequired == true
            )
        }

        let result = try JSONDecoder().decode(ResponseAccount.self, from: data)
        guard !result.passwordToken.isEmpty, !result.directoryServicesIdentifier.isEmpty else {
            throw RemoteSAPAuthenticationError.invalidResponse
        }
        return Account(
            email: email,
            password: password,
            appleId: result.appleId,
            store: result.store,
            firstName: result.firstName,
            lastName: result.lastName,
            passwordToken: result.passwordToken,
            directoryServicesIdentifier: result.directoryServicesIdentifier,
            cookie: result.cookies ?? [],
            pod: result.pod
        )
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
