import Foundation
import Security

protocol FavoritesSecureStoring {
    func loadFavorites(for key: String) -> [String]?
    @discardableResult
    func saveFavorites(_ favorites: [String], for key: String) -> Bool
}

struct FavoritesKeychainStore: FavoritesSecureStoring {
    private let service = "com.ruben.FestTime.favorites"

    func loadFavorites(for key: String) -> [String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }

        return values
    }

    @discardableResult
    func saveFavorites(_ favorites: [String], for key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(favorites) else {
            return false
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
}
