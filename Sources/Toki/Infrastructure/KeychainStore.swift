import Foundation
import Security

/// macOS Keychain への薄い wrapper。
/// Generic Password（`kSecClassGenericPassword`）を service + account で識別する。
/// OAuth token の保存／取得／削除に使う。
final class KeychainStore {
    enum KeychainStoreError: Error {
        case osStatus(OSStatus)
    }

    private let service: String

    init(service: String = "dev.pokotech.Toki") {
        self.service = service
    }

    /// 既存 entry があれば更新、なければ追加する。
    /// 値の保存形式は UTF-8 エンコードした Data。
    func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStoreError.osStatus(errSecParam)
        }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.osStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainStoreError.osStatus(updateStatus)
        }
    }

    /// 値を取得する。entry がなければ nil を返す。
    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// entry を削除する。存在しなくてもエラーにしない。
    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.osStatus(status)
        }
    }
}
