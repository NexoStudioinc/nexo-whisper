import Foundation
import SwiftUI    // Import to ensure we have access to SwiftUI types if needed

enum PredefinedPrompts {
    private static let predefinedPromptsKey = "PredefinedPrompts"

    // UUIDs estables por prompt — necesarios para que `useSystemInstructions`
    // y otras settings persistan al cambiar de idioma.
    private static let uuidByTitle: [String: UUID] = [
        "System Default":        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        "Chat":                  UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        "Email":                 UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        "Rewrite":               UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        "Formal":                UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        "Coding":                UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
        "Summary":               UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
        "Fun":                   UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
        // Traducción (Pro). UUIDs nuevos para no chocar con existentes.
        "Translate to English":  UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
        "Traducir a español":    UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    ]

    /// Compatibilidad con código existente que referencia el ID del prompt
    /// "Default" — sigue mapeando al System Default.
    static let defaultPromptId = uuidByTitle["System Default"]!

    static var all: [CustomPrompt] {
        // Devolvemos todos los templates como predefinidos, con UUID estable.
        // Esto reemplaza el viejo "Default" + "Assistant" por los 8 templates
        // pulidos (System Default + Chat + Email + Rewrite + Formal + Coding +
        // Executive Summary + Fun), cada uno con su icono propio.
        PromptTemplates.all.map { template in
            CustomPrompt(
                id: uuidByTitle[template.title] ?? UUID(),
                title: template.title,
                promptText: template.promptText,
                icon: template.icon,
                description: template.description,
                isPredefined: true,
                useSystemInstructions: true
            )
        }
    }

    static func createDefaultPrompts() -> [CustomPrompt] { all }
}
