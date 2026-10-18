import Foundation
import Security

enum Keychain {
    private static let service = "keyscore-midi-generator"
    private static let account = "openrouter-api-key"

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// 빈 값이면 항목을 지운다. 실패하면 false (호출자가 상태 표시줄에 알린다).
    @discardableResult
    static func save(_ value: String) -> Bool {
        let deleted = SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return deleted == errSecSuccess || deleted == errSecItemNotFound }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // 잠금 해제 중에만 읽고, 다른 기기(iCloud Keychain·백업 복원)로 옮기지 않는다
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
