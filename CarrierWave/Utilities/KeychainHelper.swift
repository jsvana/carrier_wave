import Foundation
import Security

// MARK: - KeychainError

enum KeychainError: Error {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
}

// MARK: - KeychainHelper

/// Thread-safe keychain access helper.
/// Keychain APIs are thread-safe at the OS level, so this type is safe to use from any context.
struct KeychainHelper: Sendable {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = KeychainHelper()

    func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func save(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, for: key)
    }

    func read(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    func readString(for key: String) throws -> String {
        let data = try read(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: Private

    private let service = "com.fullduplex.credentials"
}

// MARK: KeychainHelper.Keys

/// Keychain keys for each service
extension KeychainHelper {
    enum Keys: Sendable {
        // QRZ - token-based auth (new)
        static let qrzApiKey = "qrz.api.key"
        static let qrzCallsign = "qrz.callsign"
        static let qrzTotalUploaded = "qrz.total.uploaded"
        static let qrzTotalDownloaded = "qrz.total.downloaded"
        static let qrzLastUploadDate = "qrz.last.upload.date"
        static let qrzLastDownloadDate = "qrz.last.download.date"

        // QRZ - session-based auth (deprecated, remove after migration)
        static let qrzSessionKey = "qrz.session.key"
        static let qrzUsername = "qrz.username"

        // POTA
        static let potaIdToken = "pota.id.token"
        static let potaTokenExpiry = "pota.token.expiry"

        // LoFi
        static let lofiAuthToken = "lofi.auth.token"
        static let lofiClientKey = "lofi.client.key"
        static let lofiClientSecret = "lofi.client.secret"
        static let lofiCallsign = "lofi.callsign"
        static let lofiEmail = "lofi.email"
        static let lofiDeviceLinked = "lofi.device.linked"
        static let lofiLastSyncMillis = "lofi.last.sync.millis"

        /// HAMRS
        static let hamrsApiKey = "hamrs.api.key"

        /// Challenges
        static let challengesAuthToken = "challenges.auth.token"

        /// LoTW
        static let lotwUsername = "lotw.username"
        static let lotwPassword = "lotw.password"
        static let lotwLastQSL = "lotw.last.qsl"
        static let lotwLastQSORx = "lotw.last.qso.rx"
    }
}
