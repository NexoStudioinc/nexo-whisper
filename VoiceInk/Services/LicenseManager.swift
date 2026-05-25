import Foundation
import os

/// Almacenamiento seguro de datos de licencia.
///
/// Usa el Keychain (device-local, no syncable a iCloud) para los datos
/// sensibles: license key, instance ID de Lemon Squeezy, y timestamp de la
/// última validación contra el servidor.
///
/// Diseño tras la migración de Polar.sh → Lemon Squeezy (2026-05):
/// - Eliminado `trialStartDate`: Nexo Whisper ya no tiene trial. La
///   versión gratuita es funcional indefinidamente con features básicas.
///   Para users que tengan datos legacy con trial guardado, `migrateLegacyKeys()`
///   los limpia al primer arranque post-migración.
/// - Renombrado `activationId` → `instanceId` para alinearse con el
///   vocabulario de la API de LS.
/// - Agregado `lastValidatedAt`: necesario para implementar el TTL del
///   cache de validación (7 días — ver `LicenseViewModel`).
final class LicenseManager {
    static let shared = LicenseManager()

    private let keychain = KeychainService.shared
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseManager")

    // Identificadores en el Keychain. Mantenemos los nombres "voiceink.*"
    // por compatibilidad con instalaciones existentes (no perder datos de
    // users que ya activaron). El namespacing es opaco para el user.
    private let licenseKeyIdentifier = "voiceink.license.key"
    private let instanceIdIdentifier = "voiceink.license.instanceId"
    private let lastValidatedAtIdentifier = "voiceink.license.lastValidatedAt"

    // Identificadores legacy a borrar (datos de Polar.sh + trial).
    private let legacyActivationIdIdentifier = "voiceink.license.activationId"
    private let legacyTrialStartDateIdentifier = "voiceink.license.trialStartDate"

    private init() {
        migrateLegacyKeys()
    }

    // MARK: - License Key

    var licenseKey: String? {
        get { keychain.getString(forKey: licenseKeyIdentifier, syncable: false) }
        set {
            if let value = newValue {
                keychain.save(value, forKey: licenseKeyIdentifier, syncable: false)
            } else {
                keychain.delete(forKey: licenseKeyIdentifier, syncable: false)
            }
        }
    }

    // MARK: - Instance ID (Lemon Squeezy)

    /// `instance.id` que devuelve LS al activar la licencia en este device.
    /// Necesario para `validate` y `deactivate`. Único por (license_key, device).
    var instanceId: String? {
        get { keychain.getString(forKey: instanceIdIdentifier, syncable: false) }
        set {
            if let value = newValue {
                keychain.save(value, forKey: instanceIdIdentifier, syncable: false)
            } else {
                keychain.delete(forKey: instanceIdIdentifier, syncable: false)
            }
        }
    }

    // MARK: - Cache TTL

    /// Timestamp de la última vez que la app revalidó esta licencia contra
    /// el servidor de LS. Usado por `LicenseViewModel` para decidir cuándo
    /// re-validar (TTL de 7 días). Si `nil`, debería revalidar inmediatamente.
    var lastValidatedAt: Date? {
        get {
            guard let data = keychain.getData(forKey: lastValidatedAtIdentifier, syncable: false),
                  let timestamp = String(data: data, encoding: .utf8),
                  let timeInterval = Double(timestamp) else {
                return nil
            }
            return Date(timeIntervalSince1970: timeInterval)
        }
        set {
            if let date = newValue {
                let timestamp = String(date.timeIntervalSince1970)
                keychain.save(timestamp, forKey: lastValidatedAtIdentifier, syncable: false)
            } else {
                keychain.delete(forKey: lastValidatedAtIdentifier, syncable: false)
            }
        }
    }

    // MARK: - Cleanup

    /// Borra TODOS los datos de licencia (al deactivar desde la UI).
    func removeAll() {
        licenseKey = nil
        instanceId = nil
        lastValidatedAt = nil
    }

    /// Limpia datos legacy del esquema de Polar.sh + trial (activationId,
    /// trialStartDate). Se ejecuta una vez al primer arranque post-migración.
    /// Idempotente: si ya no hay legacy data, no hace nada.
    private func migrateLegacyKeys() {
        let hasLegacyActivation = keychain.getString(forKey: legacyActivationIdIdentifier, syncable: false) != nil
        let hasLegacyTrial = keychain.getData(forKey: legacyTrialStartDateIdentifier, syncable: false) != nil

        if hasLegacyActivation {
            // Un activationId de Polar NO sirve para LS (son namespaces distintos).
            // El user va a tener que re-activar su licencia contra LS.
            keychain.delete(forKey: legacyActivationIdIdentifier, syncable: false)
            logger.notice("🔑 Migración: borrado activationId legacy de Polar.sh")
        }

        if hasLegacyTrial {
            keychain.delete(forKey: legacyTrialStartDateIdentifier, syncable: false)
            logger.notice("🔑 Migración: borrado trialStartDate legacy")
        }

        // También limpiamos UserDefaults legacy del esquema viejo.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "VoiceInkLicenseRequiresActivation") != nil {
            defaults.removeObject(forKey: "VoiceInkLicenseRequiresActivation")
        }
        if defaults.object(forKey: "VoiceInkHasLaunchedBefore") != nil {
            defaults.removeObject(forKey: "VoiceInkHasLaunchedBefore")
        }
        if defaults.object(forKey: "VoiceInkActivationsLimit") != nil {
            defaults.removeObject(forKey: "VoiceInkActivationsLimit")
        }
    }
}
