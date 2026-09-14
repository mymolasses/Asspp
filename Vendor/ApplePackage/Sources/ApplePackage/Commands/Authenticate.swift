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
        case nextAttempt
        case failure(String)
    }

    public static func authenticate(
        email: String,
        password: String,
        code: String = "",
        cookies: [Cookie] = [],
        onVerificationRequired: (([Cookie]) async -> Void)? = nil,
        actionSignature: ((Data, Bag.BagOutput, String) async throws -> String)? = nil
    ) async throws -> Account {
        let deviceIdentifier = Configuration.deviceIdentifier.uppercased()

        let bagOutput = try await Bag.fetchBag()

        var requestEndpoint = bagOutput.authEndpoint
        var cookies: [Cookie] = cookies
        var storeFront = ""
        var pod: String?
        var currentAttempt = 1
        var redirectAttempt = 0
        var transientAttempt = 0
        var bodies: [Int: Data] = [:]

        while currentAttempt <= 3, redirectAttempt <= 3 {
            defer { currentAttempt += 1 }
            do {
                // ipatool 2.6 isolates each authentication connection while
                // retaining cookies and the SAP signer across requests.
                let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
                defer { _ = client.shutdown() }
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
                let deadline = NIODeadline.now() + .seconds(60)
                let response: HTTPClient.Response = try await client.execute(request: request, deadline: deadline).get()
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
                    transientAttempt = 0
                    requestEndpoint = uRL
                    currentAttempt -= 1 // allow one more attempt when redirect
                    redirectAttempt += 1
                    continue
                case .codeRequired:
                    await onVerificationRequired?(cookies)
                    throw ApplePackageError.verificationCodeRequired
                case .nextAttempt:
                    transientAttempt = 0
                    continue
                case .retry:
                    transientAttempt += 1
                    guard transientAttempt < 3 else {
                        try ensureFailed("Apple 登录服务暂不可用：HTTP 临时错误已重试 3 次，请稍后重试。")
                    }
                    // Keep the same Apple attempt/body but obtain a fresh SAP
                    // signature for every network retry, as Apple's client does.
                    currentAttempt -= 1
                    let delay = try authenticationRetryDelay(attempt: transientAttempt,
                                                            retryAfter: response.headers.first(name: "Retry-After"))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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

    static func shouldRetryResponse(status: Int, location: String?, body: Data?) -> Bool {
        // Populated Apple errors must reach the parser, even on HTTP 429.
        if let body, (try? decodeLoginBody(body, status: status, contentType: nil)) != nil { return false }
        return [204, 404, 429].contains(status) || (500...599).contains(status)
    }

    static func authenticationRetryDelay(attempt: Int, retryAfter: String?, now: Date = Date()) throws -> TimeInterval {
        var requested: TimeInterval?
        if let value = retryAfter?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) {
                requested = Double(value) ?? .infinity
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                requested = formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
            }
        }
        if let requested {
            guard requested <= 30 else {
                try ensureFailed("Apple 要求等待超过 30 秒，请稍后重新登录。")
            }
            return max(1, requested)
        }
        return attempt <= 1 ? 10 : 20
    }

    static func redirectURL(status: Int, location: String?, from endpoint: URL) throws -> URL? {
        guard [301, 302, 303, 307, 308].contains(status) else { return nil }
        guard let location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try ensureFailed("Apple 登录重定向异常：HTTP \(status) 缺少 Location，无法继续验证。请稍后重试。")
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
        let responseData = response.body.map { Data($0.readableBytesView) }
        if shouldRetryResponse(status: Int(response.status.code), location: response.headers.first(name: "location"), body: responseData) {
            return .retry
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
        if attempt == 1, dic["failureType"] as? String == "-5000" {
            return .nextAttempt
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
            throw ApplePackageError.invalidVerificationCode
        }

        guard response.status == .ok else {
            return .failure("Apple 登录服务返回 HTTP \(response.status.code)。")
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
