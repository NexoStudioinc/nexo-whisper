import Foundation
import os

/// Capa de gating de features para Nexo Whisper.
///
/// Punto único de consulta para toda la app: "¿este user puede usar X?".
/// Lo usan tanto la UI (para mostrar candados / disable buttons) como los
/// services (para abortar operaciones que requieren Pro).
///
/// ## Diseño
///
/// Es un enum con métodos estáticos por dos razones:
/// 1. **Múltiples puntos de chequeo (capa 4 anti-piratería)**: cada feature
///    pregunta a FeatureGate por su cuenta, en su propio call-site. Si un
///    user avanzado patchea `isPro` en un solo lugar, las otras 6-7 features
///    siguen bloqueadas. No es perfecto pero sube la barra.
/// 2. **Sin dependencias**: no requiere @EnvironmentObject ni inicialización
///    en jerarquías SwiftUI — cualquier servicio puede consultar sin que el
///    call-site sea una View.
///
/// El backing es `LicenseViewModel.shared.isPro`, que vive en `@MainActor`.
/// Cuando se invoca fuera del main thread, se hace `MainActor.assumeIsolated`
/// — el read es atómico (Bool) y no bloquea.
///
/// ## Features
///
/// Cada `Feature` representa una capacidad gateable. La granularidad es a
/// nivel de "el user nota la diferencia" — un solo enum case puede cubrir
/// 5 archivos distintos si todos sirven la misma feature de cara al user.
enum FeatureGate {

    /// Catálogo de features que requieren licencia Pro.
    enum Feature: String, CaseIterable {
        /// Modelos de transcripción que viven en internet (Groq, Deepgram,
        /// ElevenLabs, AssemblyAI, Soniox, Speechmatics, Mistral).
        /// Whisper local + Parakeet local quedan libres.
        case cloudTranscription

        /// Modos por App (a.k.a. Power Mode). Auto-cambiar prompt/modelo
        /// según el bundle ID o URL del browser activo.
        case appProfiles

        /// Pantalla "Transcribir Audio" — procesar archivos .mp3/.wav/.m4a/etc.
        /// El dictado en vivo NO está gateado por esta feature.
        case fileTranscription

        /// Mejora con IA usando una CLI local del sistema (Claude Code, Codex,
        /// Antigravity, Copilot, Pi).
        case cliEnhancement

        /// Mejora con IA usando providers cloud con API key del usuario
        /// (BYOK): Anthropic, OpenAI, Gemini, Groq, Mistral, etc.
        ///
        /// Nota importante (cambio de modelo 2026-05): originalmente BYOK
        /// era Free con la lógica "no te cobro 2 veces". Pero como Pro es
        /// one-time $7.99 (no suscripción), ese argumento no aplica — no
        /// hay cobro recurrente que se duplique. Pasó a Pro alineando con
        /// el resto del mercado (MacWhisper, Superwhisper). El escape válido
        /// para "IA gratis sin pagar nada" sigue siendo Ollama local, que
        /// queda fuera del gating.
        case byokEnhancement

        /// Acceso a los 7 prompts predefinidos extras (Chat, Email, Rewrite,
        /// Formal, Coding, Summary, Fun). El "System Default" queda libre.
        case extendedPrompts

        /// Crear / editar prompts custom propios del user. Free solo puede
        /// usar el System Default (sin posibilidad de crear nuevos).
        case customPrompts

        /// Etiqueta human-readable para mostrar en candados y tooltips.
        var displayName: String {
            switch self {
            case .cloudTranscription: return "Cloud transcription"
            case .appProfiles:        return "App Profiles"
            case .fileTranscription:  return "Audio file transcription"
            case .cliEnhancement:     return "Local CLI enhancement"
            case .byokEnhancement:    return "AI Enhancement (BYOK)"
            case .extendedPrompts:    return "Extended prompts"
            case .customPrompts:      return "Custom prompts"
            }
        }
    }

    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FeatureGate")

    /// Pregunta principal: ¿el user puede usar esta feature?
    ///
    /// Llamar desde el call-site exacto donde se va a ejecutar la feature.
    /// Evitar cachear el resultado — si el user activa una licencia, el
    /// resultado cambia inmediatamente.
    static func isAvailable(_ feature: Feature) -> Bool {
        let pro = isPro
        if !pro {
            // Log a nivel debug para diagnóstico — qué feature se bloqueó.
            // Útil para support tickets ("¿por qué no me anda X?").
            logger.debug("FeatureGate: \(feature.rawValue, privacy: .public) bloqueada (free tier)")
        }
        return pro
    }

    /// Shortcut booleano para gating sin granularidad por feature.
    /// Útil para chequeos en UI ("¿muestro el bloque Pro o el Free?").
    static var isPro: Bool {
        if Thread.isMainThread {
            // Atómico read en el thread donde vive @MainActor.
            return MainActor.assumeIsolated {
                LicenseViewModel.shared.isPro
            }
        }
        // Caller no está en main thread → hop al main de forma síncrona.
        // El read es trivial (Bool), no causa contention.
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { LicenseViewModel.shared.isPro }
        }
    }

    /// Mensaje genérico para mostrar en tooltips de candados.
    static func upgradeMessage(for feature: Feature) -> String {
        String(localized: "\(feature.displayName) requires a Pro license.")
    }

    // MARK: - Prompt gating

    /// UUID del único prompt gratis (System Default). Los demás predefinidos
    /// requieren Pro. Los UUIDs viven en `PredefinedPrompts.uuidByTitle`.
    private static let freePromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// ¿Este prompt requiere licencia Pro? `true` para los 7 predefinidos
    /// extras (Chat, Email, Rewrite, Formal, Coding, Summary, Fun) y para
    /// cualquier prompt custom creado por el user. `false` solo para el
    /// System Default que es el único free.
    ///
    /// Nota: la lógica es "todo es Pro excepto System Default" en vez de
    /// una lista enum de los pros, para que prompts custom (UUIDs random)
    /// también queden gateados sin mantenimiento extra.
    static func isPromptPro(_ promptId: UUID) -> Bool {
        return promptId != freePromptId
    }

    /// ¿Este prompt está disponible para el user actual? Combina las dos
    /// capas: si el prompt es free, siempre. Si es pro, solo con licencia.
    static func isPromptAvailable(_ promptId: UUID) -> Bool {
        if !isPromptPro(promptId) { return true }
        return isPro
    }
}
