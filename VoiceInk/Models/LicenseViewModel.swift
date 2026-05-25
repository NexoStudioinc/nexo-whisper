import Foundation
import AppKit
import os

/// ViewModel singleton para el estado de licencia de Nexo Whisper.
///
/// Reemplazó al sistema de Polar.sh + trial 7 días por:
/// - **Freemium puro**: sin trial. La versión gratis tiene transcripción
///   local (Whisper + Parakeet) + BYOK para Mejora con IA + 1 prompt
///   predefinido. La versión Pro desbloquea features adicionales (ver
///   `FeatureGate` para la lista exacta).
/// - **Backend**: Lemon Squeezy (API pública de license keys, sin secret).
/// - **Cache TTL**: una vez activada, la licencia se cachea en Keychain
///   con timestamp. Cada 7 días se re-valida contra LS para detectar
///   reembolsos, desactivaciones remotas, etc.
/// - **Tolerancia offline**: si la re-validación falla por red caída, se
///   mantiene `.licensed` hasta `offlineGracePeriodDays` (30 días). Pasado
///   ese período sin poder validar, degrada a `.free`.
///
/// Singleton para que `FeatureGate` y cualquier vista puedan consultar el
/// estado sin pasar el VM como dependencia explícita en toda la jerarquía.
@MainActor
final class LicenseViewModel: ObservableObject {
    static let shared = LicenseViewModel()

    enum LicenseState: Equatable {
        case free
        case licensed
    }

    // MARK: - Published state

    @Published private(set) var licenseState: LicenseState = .free
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false

    /// Info opcional para mostrar en la UI de licencia (límite de activaciones,
    /// email del customer, etc). `nil` cuando no hay licencia o todavía no
    /// se validó contra el servidor.
    @Published private(set) var activationLimit: Int?
    @Published private(set) var activationUsage: Int?
    @Published private(set) var customerEmail: String?

    /// Atajo para chequeos rápidos de gating de features.
    var isPro: Bool { licenseState == .licensed }

    // MARK: - Dependencies & config

    private let lemonSqueezy = LemonSqueezyService()
    private let licenseManager = LicenseManager.shared
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseViewModel")

    /// Cada cuánto se re-valida la licencia contra LS (capa 2 de seguridad).
    private let cacheTTLDays = 7

    /// Tras cuántos días sin poder revalidar (red caída sostenida) la
    /// licencia degrada a `.free`. Evita uso offline indefinido si LS está
    /// down O si el user blockea el dominio para piratear.
    private let offlineGracePeriodDays = 30

    // MARK: - Lifecycle

    init() {
        #if LOCAL_BUILD
        // Los builds locales (sin firma Apple, vía `make local`) son siempre
        // .licensed para que el desarrollador pueda usar todas las features
        // sin activar nada. Esto NO compila en builds Release/Distribución.
        //
        // EXCEPCIÓN — Debug override de QA:
        // Si el dev seteó `NexoDebugForceFreeState = true` en UserDefaults,
        // forzamos `.free` aunque LOCAL_BUILD esté activo. Útil para validar
        // que el gating de features Pro funciona bien antes del lanzamiento,
        // sin tener que hacer un build separado sin LOCAL_BUILD.
        //
        // Toggle del flag: desde Settings → sección Licencia hay un control
        // de debug visible solo en builds LOCAL_BUILD que alterna este flag.
        // O manual: `defaults write com.prakashjoshipax.VoiceInk NexoDebugForceFreeState -bool true`
        if UserDefaults.standard.bool(forKey: "NexoDebugForceFreeState") {
            licenseState = .free
            logger.notice("🔑 LOCAL_BUILD + debug override: licenseState forzado a .free (QA mode)")
        } else {
            licenseState = .licensed
            logger.notice("🔑 LOCAL_BUILD: licenseState forzado a .licensed")
        }
        #else
        loadInitialState()
        #endif
    }

    /// Solo visible/funcional en LOCAL_BUILD. Alterna el flag de debug que
    /// fuerza `.free` aunque sea build local. Útil para QA del gating Pro
    /// antes del release. En builds Release es noop.
    func toggleDebugForceFreeState() {
        #if LOCAL_BUILD
        let current = UserDefaults.standard.bool(forKey: "NexoDebugForceFreeState")
        let new = !current
        UserDefaults.standard.set(new, forKey: "NexoDebugForceFreeState")
        licenseState = new ? .free : .licensed
        logger.notice("🔑 Debug toggle: licenseState ahora \(self.licenseState == .free ? "FREE" : "LICENSED", privacy: .public)")
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        #endif
    }

    /// Lee el estado actual del flag de debug (sin alternar).
    var debugForceFreeState: Bool {
        UserDefaults.standard.bool(forKey: "NexoDebugForceFreeState")
    }

    /// `true` solo si la app se compiló con LOCAL_BUILD. La UI usa esto
    /// para mostrar/ocultar la sección de debug en Settings.
    var isDebugBuild: Bool {
        #if LOCAL_BUILD
        return true
        #else
        return false
        #endif
    }

    /// Carga el estado al arranque mirando el Keychain. No bloquea: si
    /// hay licencia cacheada, asume `.licensed` y dispara revalidación
    /// en background.
    private func loadInitialState() {
        guard let key = licenseManager.licenseKey,
              let _ = licenseManager.instanceId else {
            licenseState = .free
            return
        }

        licenseKey = key

        // Tenemos credenciales en Keychain. Asumimos .licensed y revalidamos
        // si el cache está vencido. Esto evita pantallazos de loading al
        // arranque para users con licencia válida.
        licenseState = .licensed

        if shouldRevalidate() {
            Task { await revalidateInBackground() }
        }
    }

    private func shouldRevalidate() -> Bool {
        guard let lastValidated = licenseManager.lastValidatedAt else {
            return true  // nunca se revalidó → hacelo ya
        }
        let days = Calendar.current.dateComponents([.day], from: lastValidated, to: Date()).day ?? 0
        return days >= cacheTTLDays
    }

    /// Revalida silenciosamente en background. Solo cambia el estado a
    /// `.free` si LS responde inequívocamente que la licencia NO es válida.
    /// Si falla por red, no toca el estado (capa 2 — tolerancia offline).
    private func revalidateInBackground() async {
        guard let key = licenseManager.licenseKey,
              let instanceId = licenseManager.instanceId else {
            return
        }

        do {
            let response = try await lemonSqueezy.validate(licenseKey: key, instanceId: instanceId)
            licenseManager.lastValidatedAt = Date()
            updateLicenseInfo(from: response)

            if !response.valid {
                logger.notice("🔑 Revalidación: LS reporta invalid. Degradando a .free")
                downgradeToFree(reason: "License is no longer valid")
            } else {
                logger.notice("🔑 Revalidación OK")
            }
        } catch LicenseError.keyNotFound {
            // La key dejó de existir en LS (ej. reembolso). Degradar.
            logger.notice("🔑 Revalidación: keyNotFound. Degradando a .free")
            downgradeToFree(reason: "License revoked")
        } catch {
            // Errores de red, server 5xx, etc → no degradar todavía.
            // Chequear si se superó el offline grace period.
            logger.error("🔑 Revalidación falló: \(error.localizedDescription, privacy: .public)")
            if let lastValidated = licenseManager.lastValidatedAt {
                let days = Calendar.current.dateComponents([.day], from: lastValidated, to: Date()).day ?? 0
                if days >= offlineGracePeriodDays {
                    logger.notice("🔑 Offline grace period excedido (\(days) días). Degradando a .free")
                    downgradeToFree(reason: "Could not validate license for \(days) days")
                }
            }
        }
    }

    private func updateLicenseInfo(from response: LemonSqueezyService.ValidateResponse) {
        activationLimit = response.licenseKey?.activationLimit
        activationUsage = response.licenseKey?.activationUsage
        customerEmail = response.meta?.customerEmail
    }

    private func downgradeToFree(reason: String) {
        licenseManager.removeAll()
        licenseState = .free
        licenseKey = ""
        activationLimit = nil
        activationUsage = nil
        customerEmail = nil
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
    }

    // MARK: - Public actions

    /// Abre el checkout de Lemon Squeezy en el browser.
    func openPurchaseLink() {
        if let url = URL(string: NexoURLs.buy) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Abre el customer portal de Lemon Squeezy para que el user gestione
    /// sus activaciones (deactivar otros devices, descargar invoice, etc).
    func openCustomerPortal() {
        if let url = URL(string: NexoURLs.customerPortal) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Activa una licencia en este device. Llamar desde el botón "Activate"
    /// de la UI. Si la activación falla, deja la app en `.free`.
    func validateLicense() async {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            validationSuccess = false
            validationMessage = String(localized: "Please enter a license key")
            return
        }

        isValidating = true
        defer { isValidating = false }

        let instanceName = Host.current().localizedName ?? "Unknown Mac"

        do {
            let response = try await lemonSqueezy.activate(
                licenseKey: trimmedKey,
                instanceName: instanceName
            )

            guard let instance = response.instance else {
                throw LicenseError.serverError(0)
            }

            // Persistir en Keychain
            licenseManager.licenseKey = trimmedKey
            licenseManager.instanceId = instance.id
            licenseManager.lastValidatedAt = Date()

            // Actualizar estado publicado
            licenseKey = trimmedKey
            activationLimit = response.licenseKey?.activationLimit
            activationUsage = response.licenseKey?.activationUsage
            licenseState = .licensed
            validationSuccess = true
            validationMessage = String(localized: "License activated successfully!")
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)

        } catch LicenseError.keyNotFound {
            validationSuccess = false
            validationMessage = String(localized: "License key not found. Please double-check your key and try again.")
        } catch LicenseError.activationLimitReached {
            validationSuccess = false
            validationMessage = String(localized: "This license has reached its device limit. Visit your customer portal to deactivate another device.")
        } catch LicenseError.serverError(let code) {
            validationSuccess = false
            validationMessage = String(localized: "Server error (\(code)). Please try again later or contact support.")
        } catch let urlError as URLError {
            validationSuccess = false
            logger.error("🔑 License network error: \(urlError.localizedDescription, privacy: .public)")
            validationMessage = String(localized: "Could not reach the server. Please check your internet connection and try again.")
        } catch {
            validationSuccess = false
            logger.error("🔑 Unexpected license error: \(error, privacy: .public)")
            validationMessage = String(localized: "An unexpected error occurred. Please try again or contact support at soporte@nexostudio.xyz")
        }
    }

    /// Desactiva la licencia en este device (libera el slot para otra Mac).
    /// Llama al endpoint `deactivate` de LS antes de borrar el Keychain
    /// local, para que el slot se libere en el servidor también.
    func removeLicense() async {
        if let key = licenseManager.licenseKey,
           let instanceId = licenseManager.instanceId {
            // Intentar deactivar remoto. Si falla (red caída, key revocada),
            // igual borramos el local — el slot remoto se puede limpiar
            // manualmente desde el customer portal.
            do {
                try await lemonSqueezy.deactivate(licenseKey: key, instanceId: instanceId)
            } catch {
                logger.error("🔑 Remote deactivate failed: \(error.localizedDescription, privacy: .public). Proceeding with local cleanup.")
            }
        }

        licenseManager.removeAll()
        licenseState = .free
        licenseKey = ""
        activationLimit = nil
        activationUsage = nil
        customerEmail = nil
        validationMessage = nil
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
    }
}

// Nota: `Notification.Name.licenseStatusChanged` vive en
// `Notifications/AppNotifications.swift` (declaración canónica compartida
// con otros módulos como `VoiceInkEngine`).
