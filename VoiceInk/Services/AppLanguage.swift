import Foundation
import SwiftUI
import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
}

/// Compatibilidad con call sites existentes (`AppText.t("key", language: appLanguage)`).
/// El parámetro `language` se ignora: las traducciones se resuelven desde
/// `Localizable.xcstrings` vía `NSLocalizedString`, que usa el idioma efectivo
/// del bundle (controlado por `LocalizationManager.setLanguage(_:)`).
enum AppText {
    static func t(_ key: String, language: String = "") -> String {
        NSLocalizedString(key, comment: "")
    }
}

/// Gestiona el cambio de idioma persistente para Nexo Whisper.
///
/// macOS resuelve el idioma de los strings desde `Bundle.main.preferredLocalizations`,
/// que a su vez se calcula a partir de `UserDefaults.standard.array(forKey: "AppleLanguages")`.
/// Cambiar ese array no afecta a la sesión en curso (los bundles ya cargaron sus
/// strings); por eso, después de cada cambio se ofrece reiniciar la app.
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    private let appleLanguagesKey = "AppleLanguages"
    private let appLanguageKey = "appLanguage"
    /// Última lengua aplicada efectivamente. Necesario porque `@AppStorage`
    /// en SettingsView escribe `appLanguage` ANTES de que setLanguage corra,
    /// así que no se puede usar `appLanguage` para detectar cambio real.
    private let lastAppliedKey = "appLanguageLastApplied"

    private init() {}

    /// Idioma actualmente seleccionado por el usuario en la app.
    ///
    /// Si el user nunca eligió idioma manualmente, detectamos su preferencia
    /// del sistema:
    ///   - macOS en español (cualquier variante: es, es-AR, es-MX, etc.) → ES
    ///   - macOS en portugués → PT (si está soportado en el enum)
    ///   - Cualquier otro → EN (default global)
    ///
    /// Esa detección corre solo la PRIMERA vez. Apenas el user toca el
    /// picker de idioma en Settings, `setLanguage` escribe a UserDefaults
    /// y futuros arranques respetan esa elección.
    var currentLanguage: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: appLanguageKey),
           let lang = AppLanguage(rawValue: stored) {
            return lang
        }

        // Sin preferencia guardada → auto-detect del sistema.
        let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
        let detected: AppLanguage
        switch systemLang {
        case "es":
            detected = .spanish
        case "pt":
            // Si AppLanguage tiene .portuguese, usarlo; si no, EN como fallback.
            detected = AppLanguage(rawValue: "pt") ?? .english
        default:
            detected = .english
        }

        // Persistir la detección para que sea consistente en próximos arranques
        // (y para que `lastAppliedKey` de setLanguage no se confunda).
        UserDefaults.standard.set(detected.rawValue, forKey: appLanguageKey)
        return detected
    }

    /// Cambia el idioma activo. Persiste la elección y muestra una alerta
    /// pidiendo reiniciar la app para que el cambio tome efecto.
    func setLanguage(_ language: AppLanguage) {
        let lastApplied = UserDefaults.standard.string(forKey: lastAppliedKey)
        guard lastApplied != language.rawValue else { return }

        UserDefaults.standard.set(language.rawValue, forKey: appLanguageKey)
        UserDefaults.standard.set([language.rawValue], forKey: appleLanguagesKey)
        UserDefaults.standard.set(language.rawValue, forKey: lastAppliedKey)
        UserDefaults.standard.synchronize()

        // Diferimos la alerta para salir del callback de `.onChange` de
        // SwiftUI. Si corriéramos `runModal()` directo desde el .onChange,
        // SwiftUI suprime el modal porque está en medio de un body update.
        // Además forzamos la app al frente para que la alerta sea visible
        // sí o sí (no quede tapada por otras apps en primer plano).
        DispatchQueue.main.async { [weak self] in
            self?.presentRestartAlert(for: language)
        }
    }

    private func presentRestartAlert(for language: AppLanguage) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Restart required", comment: "")
        alert.informativeText = NSLocalizedString(
            "Nexo Whisper needs to restart to apply the new language.",
            comment: ""
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Restart now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            relaunchApp()
        }
    }

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
