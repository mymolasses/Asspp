//
//  Errors.swift
//  ApplePackage
//
//  Created by luca on 15.09.2025.
//

import Foundation

public enum ApplePackageError: Error {
    case licenseRequired
    case sessionExpired
    case verificationCodeRequired
    case invalidVerificationCode

    static func checkSession(_ response: [String: Any]) throws {
        let code = response["failureType"].map { String(describing: $0) }
        if ["2034", "2042", "1008"].contains(code ?? "") ||
            response["customerMessage"] as? String == Strings.passwordChanged {
            throw ApplePackageError.sessionExpired
        }
    }
}

extension ApplePackageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .licenseRequired:
            return "该账号尚未获取此 App 的许可证，请先请求购买。"
        case .sessionExpired:
            return "Apple 登录已失效，请刷新令牌；需要验证码时请在账号详情输入。"
        case .verificationCodeRequired:
            return "Apple 要求输入双重认证验证码。"
        case .invalidVerificationCode:
            return "双重认证验证码无效或已过期，请获取新验证码后重试。"
        }
    }
}
