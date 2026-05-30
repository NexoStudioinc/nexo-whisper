import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Provider de IA local usando **Apple Intelligence (Foundation Models)**:
/// LLM on-device, gratis, privado, sin API key ni internet. Disponible en
/// macOS 26+ con Apple Intelligence activado y chip compatible (M1+).
///
/// Aislado tras `#available`/`#if canImport` para que la app siga compilando y
/// corriendo en macOS 15 (el provider simplemente no aparece como disponible).
enum AppleFoundationService {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "AppleFoundationService"
    )

    /// ¿Está disponible Apple Intelligence en este equipo ahora mismo?
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        #endif
        return false
    }

    /// Motivo legible si NO está disponible (para mostrar en Settings).
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return String(localized: "Your Mac isn't compatible with Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return String(localized: "Enable Apple Intelligence in System Settings.")
            case .unavailable(.modelNotReady):
                return String(localized: "Apple's model is downloading or not ready yet.")
            case .unavailable:
                return String(localized: "Apple Intelligence isn't available.")
            }
        }
        #endif
        return String(localized: "Apple Intelligence requires macOS 26 or later.")
    }

    /// Genera una respuesta con el modelo on-device de Apple.
    static func generate(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw NSError(
            domain: "AppleFoundationService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence isn't available on this device.")]
        )
    }
}
