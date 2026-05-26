import Foundation
import Security
import os

/// Almacenamiento de credenciales (license key, instance ID, API keys).
///
/// IMPORTANTE: usamos UserDefaults en vez del Keychain real porque la app
/// está ad-hoc signed sin Apple Developer Team ID. Sin un App Identifier
/// estable, el Keychain de macOS NO persiste los items entre relanzamientos
/// (cada launch se asigna un identifier distinto y los items no se encuentran).
///
/// Resultado: si usábamos Keychain, el user activaba la licencia, cerraba
/// la app, abría de nuevo → volvía a `.free`. Bug fixeado 2026-05-26.
///
/// Cuando tengamos Apple Developer Account (con Team ID estable), podemos
/// migrar a Keychain real para mayor seguridad. Por ahora, UserDefaults
/// es la única opción que funciona consistentemente.
final class KeychainService {
    static let shared = KeychainService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeychainService")
    private let service = "com.prakashjoshipax.VoiceInk"

    private let defaults = UserDefaults.standard
    private let localPrefix = "LocalKeychain_"

    private init() {}

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(_ value: String, forKey key: String, syncable: Bool = true) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data for key: \(key, privacy: .public)")
            return false
        }
        return save(data: data, forKey: key, syncable: syncable)
    }

    /// Saves data (a UserDefaults bajo el prefix localPrefix).
    @discardableResult
    func save(data: Data, forKey key: String, syncable: Bool = true) -> Bool {
        defaults.set(data, forKey: localPrefix + key)
        return true
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves data desde UserDefaults bajo el prefix localPrefix.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        return defaults.data(forKey: localPrefix + key)
    }

    /// Deletes an item.
    @discardableResult
    func delete(forKey key: String, syncable: Bool = true) -> Bool {
        defaults.removeObject(forKey: localPrefix + key)
        return true
    }

    /// Checks if a key exists.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        return defaults.data(forKey: localPrefix + key) != nil
    }

    // MARK: - Private Helpers

    #if false  // Disabled — ver doc en top de archivo. Mantenido por si volvemos a Keychain real con Developer ID.
    private func baseQuery(forKey key: String, syncable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]

        if syncable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        return query
    }
    #endif
}
