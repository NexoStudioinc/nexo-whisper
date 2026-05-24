import Foundation

struct TemplatePrompt: Identifiable {
    let id: UUID
    let title: String
    let promptText: String
    let icon: PromptIcon
    let description: String

    func toCustomPrompt() -> CustomPrompt {
        CustomPrompt(
            id: UUID(),
            title: title,
            promptText: promptText,
            icon: icon,
            description: description,
            isPredefined: false
        )
    }
}

/// Templates de prompts predefinidos para el enhancement con IA.
///
/// Bilingual: los `promptText` se devuelven en ES o EN según el idioma
/// actual de la app. Cuando el usuario está en ES, el LLM recibe instrucciones
/// en ES y produce output más natural para dictados en castellano.
///
/// Se pulieron drásticamente vs. la versión original de VoiceInk:
/// - Reglas comprimidas (de 12 bullets a 6-7 por template).
/// - Sin redundancia (la regla de números/listas vive en el wrapper SYSTEM).
/// - Tono adaptado: ES rioplatense ("dictado", "limpiá", "no inventes").
enum PromptTemplates {
    static var all: [TemplatePrompt] {
        createTemplatePrompts()
    }

    static func createTemplatePrompts() -> [TemplatePrompt] {
        let isES = (UserDefaults.standard.string(forKey: "appLanguage") ?? "en") == "es"
        return isES ? createTemplatePromptsES() : createTemplatePromptsEN()
    }

    // MARK: - English templates

    private static func createTemplatePromptsEN() -> [TemplatePrompt] {
        [
            TemplatePrompt(
                id: UUID(),
                title: "System Default",
                promptText: """
                    - Keep the original meaning, tone and language of the speaker.
                    - Fix grammar, remove fillers ("uh", "um", "like", "you know") and stutters, collapse repetitions.
                    - Handle self-corrections: if the speaker corrects mid-sentence ("scratch that", "I mean", "actually X"), keep only the corrected version.
                    - Respect explicit formatting commands: "new line" / "new paragraph" inserts the break.
                    - Detect lists: numbered sequences → ordered list; non-numbered items → bullets.
                    - Write numbers as numerals (5, not "five"), normalize abbreviations (vs., etc.), keep names and proper nouns intact.
                    - Organize into short paragraphs of 2–4 sentences.
                    """,
                icon: "checkmark.seal.fill",
                description: "Cleans up the transcription preserving meaning and tone"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Chat",
                promptText: """
                    - Rewrite as an informal chat message: short, natural, conversational.
                    - Keep emojis if present, do not invent new ones.
                    - Light grammar fix, remove fillers, preserve the speaker's voice.
                    - Short lines, natural breaks. No greetings or sign-offs.
                    - Numbers as numerals (5, not "five").
                    """,
                icon: "bubble.left.and.bubble.right.fill",
                description: "Casual chat-style formatting"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Email",
                promptText: """
                    - Format as a complete email: greeting (Hi), body in 2–4 sentence paragraphs, closing (Thanks).
                    - Clear, friendly, non-formal language unless the dictation is clearly professional — match that tone instead.
                    - Fix grammar, remove fillers, preserve all facts, names, dates and action items.
                    - Numbers as numerals (5, not "five"); format dates and times consistently.
                    - Do not invent content not present in the dictation.
                    """,
                icon: "envelope.fill",
                description: "Professional email formatting"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Rewrite",
                promptText: """
                    - Rewrite for clarity and natural flow while preserving meaning, tone and voice.
                    - Improve sentence structure and word choice without changing intent.
                    - Fix grammar and spelling, remove fillers, collapse repetitions.
                    - Format lists as bullets or numbered when appropriate.
                    - Numbers as numerals (5, not "five").
                    - Organize into 2–4 sentence paragraphs.
                    - Keep all names, numbers, dates and facts exactly as they appear.
                    """,
                icon: "pencil.circle.fill",
                description: "Rewrites for clarity and flow"
            )
        ]
    }

    // MARK: - Spanish (rioplatense)

    private static func createTemplatePromptsES() -> [TemplatePrompt] {
        [
            TemplatePrompt(
                id: UUID(),
                title: "System Default",
                promptText: """
                    - Conservá el significado, tono e idioma original del hablante.
                    - Corregí gramática, sacá muletillas ("eh", "este", "o sea", "viste") y tartamudeos, colapsá repeticiones.
                    - Manejá autocorrecciones: si el hablante se corrige a mitad de frase ("no, mejor", "perdón quise decir", "en realidad X"), dejá solo la versión corregida.
                    - Respetá comandos explícitos de formato: "nueva línea" / "nuevo párrafo" insertan el salto.
                    - Detectá listas: secuencias numeradas → lista ordenada; items sin numerar → bullets.
                    - Escribí números como cifras (5, no "cinco"), normalizá abreviaturas (vs., etc.), respetá nombres propios.
                    - Organizá en párrafos cortos de 2–4 oraciones.
                    """,
                icon: "checkmark.seal.fill",
                description: "Limpia la transcripción preservando significado y tono"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Chat",
                promptText: """
                    - Reescribí como mensaje de chat informal: corto, natural, conversacional.
                    - Mantené emojis si los hay, no inventes nuevos.
                    - Corrección leve de gramática, sin muletillas, conservando la voz del hablante.
                    - Líneas cortas, cortes naturales. Sin saludos ni despedidas.
                    - Números como cifras (5, no "cinco").
                    """,
                icon: "bubble.left.and.bubble.right.fill",
                description: "Formato informal estilo chat"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Email",
                promptText: """
                    - Formateá como email completo: saludo (Hola), cuerpo en párrafos de 2–4 oraciones, cierre (Saludos).
                    - Lenguaje claro y amable, no formal — salvo que el dictado claramente lo sea, en ese caso mantené el tono.
                    - Corregí gramática, sacá muletillas, conservá todos los datos: nombres, fechas, acciones a tomar.
                    - Números como cifras (5, no "cinco"); formato consistente para fechas y horas.
                    - No inventes contenido que no esté en el dictado.
                    """,
                icon: "envelope.fill",
                description: "Formato de email profesional"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Rewrite",
                promptText: """
                    - Reescribí para mejorar claridad y fluidez conservando significado, tono y voz.
                    - Mejorá estructura de oraciones y elección de palabras sin cambiar la intención.
                    - Corregí gramática y ortografía, sacá muletillas, colapsá repeticiones.
                    - Formateá listas con bullets o numeradas cuando corresponda.
                    - Números como cifras (5, no "cinco").
                    - Organizá en párrafos de 2–4 oraciones.
                    - Mantené todos los nombres, números, fechas y datos exactamente como aparecen.
                    """,
                icon: "pencil.circle.fill",
                description: "Reescribe para más claridad y fluidez"
            )
        ]
    }
}
