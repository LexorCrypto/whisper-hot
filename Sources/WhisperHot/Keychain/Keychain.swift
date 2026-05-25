import Foundation
import Security

/// Minimal wrapper around Keychain Services for generic-password items.
/// Stores with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and disables iCloud sync.
enum Keychain {
    enum Account: String {
        case openAI = "openai-api-key"
        case openRouter = "openrouter-api-key"
        case groq = "groq-api-key"
        case polzaAI = "polzaai-api-key"
        case customEndpoint = "custom-endpoint-api-key"
        /// 32-byte random key used by HistoryStore for AES-GCM at-rest
        /// encryption of the transcript history file. Generated on first use
        /// and never exposed in the UI.
        case historyEncryptionKey = "history-encryption-key"
    }

    enum KeychainError: Error, LocalizedError {
        case itemNotFound
        case invalidData
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .itemNotFound: return "Keychain item not found."
            case .invalidData: return "Keychain item contains invalid data."
            case .unexpectedStatus(let status): return "Keychain error (OSStatus \(status))."
            }
        }
    }

    /// Service identifier used in all generic-password Keychain queries.
    /// The optional `service:` parameter on each public function defaults to
    /// this value; tests can pass a unique service prefix to keep test
    /// entries isolated from the user's real keychain.
    static let defaultService = "com.aleksejsupilin.WhisperHot"

    static func save(apiKey: String, account: Account, service: String = defaultService) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try saveRaw(data, account: account, service: service)
    }

    static func readAPIKey(account: Account, service: String = defaultService) throws -> String {
        let data = try readRaw(account: account, service: service)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    static func delete(account: Account, service: String = defaultService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
        if status == errSecSuccess {
            postChangeNotification()
        }
    }

    // MARK: - Raw Data (non-API-key payloads, e.g. encryption keys)

    static func saveData(_ data: Data, account: Account, service: String = defaultService) throws {
        try saveRaw(data, account: account, service: service)
    }

    static func readData(account: Account, service: String = defaultService) throws -> Data {
        try readRaw(account: account, service: service)
    }

    // MARK: - Internals

    /// Write an arbitrary Data payload, doing an SecItemUpdate first and
    /// falling back to SecItemAdd. Shared by `save(apiKey:)` and `saveData(_:)`.
    private static func saveRaw(_ data: Data, account: Account, service: String) throws {
        // Search for the existing item by class + service + account. These
        // three fields alone identify a generic-password record; everything
        // else (value, accessibility, sync) belongs in the attributes dict.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            postChangeNotification()
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        // No existing item → add a fresh one with the full attribute set.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
        postChangeNotification()
    }

    /// Read raw Data for a generic-password record. Shared by `readAPIKey(account:)`
    /// and `readData(account:)`.
    private static func readRaw(account: Account, service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        return data
    }

    private static func postChangeNotification() {
        NotificationCenter.default.post(name: .whisperHotKeychainDidChange, object: nil)
    }
}
