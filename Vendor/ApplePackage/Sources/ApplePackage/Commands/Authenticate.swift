//
//  Authenticate.swift
//  ApplePackage
//
//  Created by QAQ on 2023/10/4.
//

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

public enum Authenticator {
    enum LoginResponse {
        case success(Account)
        case codeRequired
        case redirect(URL)
        case retry
        case failure(String)
    }

    public static func authenticate(
        email: String,
        password: String,
        code: String = "",
        cookies: [Cookie] = [],
        actionSignature: ((Data, Bag.BagOutput, String) async throws -> String)? = nil
    ) async throws -> Account {
        let deviceIdentifier = Configuration.deviceIdentifier.uppercased()

        let bagOutput = try await Bag.fetchBag()

        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        var requestEndpoint: URL = try createInitialRequestEndpoint(baseURL: bagOutput.authEndpoint, deviceIdentifier: deviceIdentifier)
        var cookies: [Cookie] = cookies
        var storeFront = ""
        var pod: String?
        var currentAttempt = 1
        var redirectAttempt = 0
        var bodies: [Int: Data] = [:]

        while currentAttempt <= 3, redirectAttempt <= 3 {
            defer { currentAttempt += 1 }
            do {
                let requestAttempt = redirectAttempt > 0 ? 1 : currentAttempt
                let data: Data
                if let saved = bodies[requestAttempt] {
                    data = saved
                } else {
                    data = try authenticationBody(email: email, password: password, code: code,
                                                  deviceIdentifier: deviceIdentifier, attempt: requestAttempt)
                    bodies[requestAttempt] = data
                }
                var request = try makeRequest(
                    endpoint: requestEndpoint,
                    email: email,
                    password: password,
                    code: code,
                    cookies: cookies,
                    deviceIdentifier: deviceIdentifier,
                    body: data
                )
                if let actionSignature {
                    request.headers.add(name: "X-Apple-ActionSignature", value: try await actionSignature(data, bagOutput, deviceIdentifier))
                }
                let response = try await sendLoginRequest(client: client, request: request, endpoint: requestEndpoint, cookies: &cookies)
                let result = try parseResponse(
                    response,
                    endpoint: requestEndpoint,
                    email: email,
                    password: password,
                    code: code,
                    cookies: &cookies,
                    storeFront: &storeFront,
                    pod: &pod,
                    attempt: currentAttempt
                )
                switch result {
                case let .success(account):
                    return account
                case let .redirect(uRL):
                    requestEndpoint = uRL
                    currentAttempt -= 1 // allow one more attempt when redirect
                    redirectAttempt += 1
                    continue
                case .codeRequired:
                    currentAttempt += 65535 // stop attempts
                    try ensureFailed(Strings.authRequiresVerificationCode)
                case .retry:
                    try await Task.sleep(nanoseconds: 250_000_000)
                    continue
                case let .failure(string):
                    try ensureFailed("\(Strings.authFailed): \(string)")
                }
            } catch {
                // Do not turn malformed responses, signing failures or bad codes
                // into new credential attempts. Transport retries happen below.
                throw error
            }
        }

        try ensureFailed("Apple 登录超过允许的重定向或认证次数，请稍后重试。")
    }

    private static func sendLoginRequest(client: HTTPClient, request: HTTPClient.Request, endpoint: URL, cookies: inout [Cookie]) async throws -> HTTPClient.Response {
        let deadline = NIODeadline.now() + .seconds(60)
        var request = request
        for attempt in 1...3 {
            try Task.checkCancellation()
            let response: HTTPClient.Response = try await client.execute(request: request, deadline: deadline).get()
            cookies.mergeCookies(response.cookies)
            let retry = shouldRetryResponse(status: Int(response.status.code),
                location: response.headers.first(name: "location"),
                body: response.body.map { Data($0.readableBytesView) })
            if !retry || attempt == 3 { return response }
            APLogger.info("auth: retrying anomalous response HTTP \(response.status.code), transport attempt \(attempt)")
            // Preserve signed XML bytes and signature; carry response cookies
            // forward just like the reference client's cookie jar.
            request.headers.remove(name: "Cookie")
            for (name, value) in cookies.buildCookieHeader(endpoint) {
                request.headers.add(name: name, value: value)
            }
            try await Task.sleep(nanoseconds: UInt64(attempt) * 250_000_000)
        }
        try ensureFailed(Strings.authFailedUnknown)
    }

    static func shouldRetryResponse(status: Int, location: String?, body: Data?) -> Bool {
        if [204, 404, 429, 500, 502, 503, 504].contains(status) { return true }
        if [301, 302, 303, 307, 308].contains(status) {
            return location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        if status == 200 {
            return (try? decodeLoginBody(body ?? Data(), status: status, contentType: nil)) == nil
        }
        return false
    }

    static func redirectURL(status: Int, location: String?, from endpoint: URL) throws -> URL? {
        guard [301, 302, 303, 307, 308].contains(status) else { return nil }
        guard let location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try ensureFailed("Apple 登录重定向异常：HTTP \(status) 缺少 Location（已重试）。未发送到任何猜测地址，请稍后重试或检查代理网络。")
        }
        guard let url = URL(string: location.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: endpoint)?.absoluteURL,
              url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              host.hasSuffix(".itunes.apple.com"), url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443 else {
            try ensureFailed("Apple 登录返回不可信重定向，已停止发送登录信息。")
        }
        return url
    }

    static func decodeLoginBody(_ data: Data, status: Int, contentType: String?) throws -> [String: Any] {
        let plistData = Bag.extractPlistData(from: data)
        guard let value = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dictionary = value as? [String: Any] else {
            // Metadata only: never surface body contents (which can contain tokens).
            try ensureFailed("Apple 登录响应不是有效 plist：HTTP \(status)，类型 \(contentType ?? "未知")，\(data.count) 字节。可能是空响应或网络错误页面，请稍后重试或检查代理网络。")
        }
        return dictionary
    }

    public static func rotatePasswordToken(for account: inout Account) async throws {
        let newAccount = try await authenticate(
            email: account.email,
            password: account.password,
            code: "",
            cookies: account.cookie
        )
        account = newAccount
    }

    private static func createInitialRequestEndpoint(
        baseURL: URL,
        deviceIdentifier: String
    ) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            try ensureFailed("\(Strings.invalidAuthEndpoint): \(baseURL)")
        }
        comps.queryItems = (comps.queryItems ?? []).filter { $0.name != "guid" } + [URLQueryItem(name: "guid", value: deviceIdentifier)]
        return try comps.url.get()
    }

    private static func makeRequest(
        endpoint: URL,
        email: String,
        password: String,
        code: String,
        cookies: [Cookie],
        deviceIdentifier: String,
        body data: Data
    ) throws -> HTTPClient.Request {
        var headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Content-Type", "application/x-www-form-urlencoded"),
            ("Accept", "application/x-apple-plist, application/xml"),
            ("Accept-Encoding", "identity"),
        ]
        for item in cookies.buildCookieHeader(endpoint) {
            headers.append(item)
        }
        return try .init(url: endpoint.absoluteString, method: .POST, headers: .init(headers), body: .data(data))
    }

    private static func authenticationBody(email: String, password: String, code: String, deviceIdentifier: String, attempt: Int) throws -> Data {
        let parameters: [String: String] = [
            "appleId": email,
            "attempt": "\(attempt)",
            "guid": deviceIdentifier,
            "password": "\(password)\(code)",
            "rmp": "0",
            "why": "signIn",
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: parameters,
            format: .xml,
            options: 0
        )
    }

    static func parseResponse(
        _ response: HTTPClient.Response,
        endpoint: URL,
        email: String,
        password: String,
        code: String,
        cookies: inout [Cookie],
        storeFront: inout String,
        pod: inout String?,
        attempt: Int
    ) throws -> LoginResponse {
        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes
        )

        cookies.mergeCookies(response.cookies)
        if [204, 404, 429, 500, 502, 503, 504].contains(Int(response.status.code)) {
            return .failure("Apple 登录服务暂不可用：HTTP \(response.status.code)（已重试）。")
        }

        let readStoreFrontValue = response
            .headers["x-set-apple-store-front"]
            .filter { !$0.isEmpty }
        assert(readStoreFrontValue.count <= 1)
        if let first = readStoreFrontValue.first {
            storeFront = first
        }

        if let podValue = response.headers.first(name: "pod"), !podValue.isEmpty {
            pod = podValue
            APLogger.info("auth: received pod value: \(podValue)")
        }

        if let url = try redirectURL(status: Int(response.status.code), location: response.headers.first(name: "location"), from: endpoint) {
            return .redirect(url)
        }

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            return .failure("response body is empty (code: \(response.status.code))")
        }

        let dic = try decodeLoginBody(data, status: Int(response.status.code), contentType: response.headers.first(name: "content-type"))
        guard response.status == .ok else {
            return .failure("Apple 登录服务返回 HTTP \(response.status.code)。")
        }
        if attempt == 1, dic["failureType"] as? String == "-5000" {
            return .retry
        }

        if let failureType = dic["failureType"] as? String,
           failureType.isEmpty,
           code.isEmpty,
           let customerMessage = dic["customerMessage"] as? String,
           customerMessage == "MZFinance.BadLogin.Configurator_message"
        {
            return .codeRequired
        }

        if let failureType = dic["failureType"] as? String, failureType == "5005" {
            return .failure(Strings.invalid2FACode)
        }

        let failureMessage = (dic["dialog"] as? [String: Any])?["explanation"] as? String ?? (dic["customerMessage"] as? String)
        let accountInfoDic = try (dic["accountInfo"] as? [String: Any]).get(failureMessage ?? Strings.missingAccountInfo)
        let addressInfoDic = try (accountInfoDic["address"] as? [String: Any]).get(failureMessage ?? Strings.missingAddress)

        let account = try Account(
            email: email,
            password: password,
            appleId: accountInfoDic["appleId"] as? String,
            store: storeFront,
            firstName: addressInfoDic["firstName"] as? String,
            lastName: addressInfoDic["lastName"] as? String,
            passwordToken: dic["passwordToken"] as? String,
            directoryServicesIdentifier: dic["dsPersonId"] as? String,
            cookie: cookies,
            pod: pod
        )
        return .success(account)
    }
}
