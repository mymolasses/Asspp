//
//  AuthenticationService.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Foundation
import Logging

extension AppStore {
    enum AuthenticationError: Error {
        case accountNotFound
    }

    @MainActor
    func authenticate(email: String, password: String, code: String) async throws -> UserAccount {
        logger.info("starting authentication for user")
        do {
            let appleAccount = try await LocalSAPAuthenticator.authenticate(
                email: email, password: password, code: code, cookies: []
            )
            let userAccount = save(email: email, account: appleAccount)
            logger.info("authentication successful for user")
            return userAccount
        } catch {
            logger.error("authentication failed for user: \(error.localizedDescription)")
            throw error
        }
    }

    @MainActor
    @discardableResult
    func rotate(id: UserAccount.ID, code: String = "") async throws -> UserAccount? {
        guard !refreshingAccountIDs.contains(id) else {
            throw NSError(domain: "Asspp.Session", code: 1, userInfo: [NSLocalizedDescriptionKey: "此账号正在刷新令牌，请稍候再试。"])
        }
        refreshingAccountIDs.insert(id)
        defer { refreshingAccountIDs.remove(id) }
        logger.info("starting account rotation for user id: \(id)")
        guard let account = accounts.first(where: { $0.id == id }) else {
            logger.error("account not found for rotation, id: \(id)")
            throw AuthenticationError.accountNotFound
        }
        do {
            let newAppleAccount = try await LocalSAPAuthenticator.authenticate(
                email: account.account.email,
                password: account.account.password,
                code: code,
                // A 2FA code starts a new authentication transaction. Reusing
                // stale challenge cookies after an earlier failed login can be
                // rejected by Apple with HTTP 403.
                cookies: code.isEmpty ? account.account.cookie : []
            )
            let updatedAccount = save(email: account.account.email, account: newAppleAccount)
            logger.info("account rotation successful for user id: \(id)")
            return updatedAccount
        } catch {
            sessionErrors[id] = "刷新登录失败：\(error.localizedDescription)\n请打开账号详情重试，需要时输入 2FA 验证码。"
            logger.error("account rotation failed for user id: \(id): \(error.localizedDescription)")
            throw error
        }
    }
}
