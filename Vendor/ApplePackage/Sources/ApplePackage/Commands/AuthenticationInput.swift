import Foundation

/// Routing rules from ipatool v2.7.0. Keep the identifier sent to Apple intact.
public enum AuthenticationInput {
    public static func phoneNumberStorefront(_ appleID: String) -> String? {
        var number = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        var international = false
        if number.hasPrefix("+") { international = true; number.removeFirst() }
        else if number.hasPrefix("00") { international = true; number.removeFirst(2) }
        guard !number.isEmpty, number.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        if number.count == 13, number.hasPrefix("861") { return Configuration.storeId(for: "CN") }
        if number.count == 12, number.hasPrefix("91") { number.removeFirst(2) }
        else if international { return nil }
        if number.count == 11, number.hasPrefix("1") { return Configuration.storeId(for: "CN") }
        if !international, number.count == 11, number.hasPrefix("0") { number.removeFirst() }
        if number.count == 10, let first = number.first, ("6"..."9").contains(first) {
            return Configuration.storeId(for: "IN")
        }
        return nil
    }

    public static func normalizeVerificationCode(_ input: String) throws -> String {
        if input.isEmpty { return "" }
        var code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.hasPrefix("\u{1B}[200~"), code.hasSuffix("\u{1B}[201~") {
            code.removeFirst(6)
            code.removeLast(6)
        }
        code = code.filter { !$0.isWhitespace }
        guard code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw ApplePackageError.invalidVerificationCode
        }
        return code
    }
}
