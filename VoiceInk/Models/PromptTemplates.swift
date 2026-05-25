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
                    CRITICAL: NEVER delete words, sentences, or ideas from the dictation. Preserve ALL content. The goal is light cleanup, not rewriting.

                    What to do:
                    - Fix only punctuation (commas, periods, question marks, exclamation marks, capitalization).
                    - Normalize spelling and accents — without changing the speaker's word choices.
                    - Collapse only OBVIOUS transcription stutters (e.g. "the-the-the car" → "the car"). If the speaker intentionally repeated for emphasis, KEEP the repetition.
                    - If the speaker dictated numbers as digits ("5"), keep them as digits. If they said the word ("five"), keep the word.
                    - If the speaker mixes languages (e.g. Spanish with English words like "download", "meeting", "deploy", "frontend"), KEEP the exact words as dictated — do not translate.
                    - Insert line breaks only if the speaker explicitly said "new line" or "new paragraph".

                    What NOT to do:
                    - Do NOT remove fillers ("uh", "um", "like", "you know"). They are part of natural speech and the user wants them preserved.
                    - Do NOT collapse intentional repetitions.
                    - Do NOT "fix" self-corrections by deleting the first version. If they said "I'll go tomorrow, no, actually Thursday", keep it as-is.
                    - Do NOT add lists, bullets, headers, or any formatting the speaker didn't request.
                    - Do NOT add greetings, sign-offs, or summaries.
                    - Do NOT rephrase, paraphrase, or "improve" the speaker's word choices.
                    """,
                icon: "checkmark.seal.fill",
                description: "Minimal cleanup: fixes punctuation, preserves everything else"
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
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Formal",
                promptText: """
                    - Rewrite in a professional, formal register suitable for contracts, legal documents and business communication.
                    - Use complete sentences, precise vocabulary, no contractions, no slang, no fillers.
                    - Prefer active voice when natural; passive voice only if the dictation clearly calls for it.
                    - Fix grammar and punctuation; collapse repetitions; keep all facts, names, dates and figures exact.
                    - Numbers as numerals (5, not "five"); spell out abbreviations on first use if ambiguous.
                    - Organize into 2–4 sentence paragraphs. Do not add salutations or closings.
                    - Do not invent content not present in the dictation.
                    """,
                icon: "briefcase.fill",
                description: "Professional formal tone for business and legal docs"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Coding",
                promptText: """
                    - Convert the dictation into clean code-ready text.
                    - Wrap identifiers, function names, file paths, flags and commands in backticks.
                    - Format code blocks with triple backticks when the speaker dictates more than one line of code; infer the language if obvious, otherwise leave it blank.
                    - Use conventional naming: camelCase for variables/functions, PascalCase for types, kebab-case for CLI flags, SCREAMING_SNAKE for constants.
                    - Spelled-out symbols become punctuation: "open paren" → `(`, "equals" → `=`, "arrow" → `->`, "new line" inserts a line break.
                    - Keep prose outside code blocks short and direct. No fillers, no repetitions.
                    - Do not invent code: only what the speaker dictated.
                    """,
                icon: "terminal.fill",
                description: "Voice to code with backticks, identifiers and conventions"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Summary",
                promptText: """
                    - Condense the dictation into an executive summary: 3 to 5 actionable bullets.
                    - Each bullet starts with a verb and states a concrete action, decision or finding.
                    - Drop filler, anecdotes and side comments; keep only what matters for a decision-maker.
                    - Preserve every key fact: names, dates, figures, deadlines, owners.
                    - Numbers as numerals; format dates and amounts consistently.
                    - No greetings, no closings, no preamble — only the bullets.
                    - Do not invent content not present in the dictation.
                    """,
                icon: "list.clipboard.fill",
                description: "Turns a long dictation into 3–5 actionable bullets"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Fun",
                promptText: """
                    Rewrite the transcript in a WILDLY playful, exaggerated tone. Pick ONE absurd style at random for each request — don't always do the same thing. Possible styles (rotate):
                    - Drunk/tipsy storyteller: rambling, slurred-feeling, with random tangents.
                    - Overdramatic narrator: like a movie trailer voice, everything is epic.
                    - Excited 12-year-old: lots of energy, exaggerations, "literally", "OMG".
                    - Sarcastic friend: dry humor, ironic asides.
                    - Pirate / Cowboy / Medieval bard: pick one persona briefly.

                    Hard rules:
                    - Keep all facts, names, dates, numbers EXACTLY as dictated. Don't change WHAT was said, only HOW.
                    - Don't invent new content — embellish what's there.
                    - Stay readable (no walls of capitals, max 2 exclamation marks total).
                    - Allow 1-3 emojis if they really fit the persona (a beer 🍺 for drunk, a sword ⚔️ for pirate, etc).
                    - End within 2-3 sentences of the original length — don't go on forever.
                    - Numbers as numerals.
                    """,
                icon: "face.smiling.fill",
                description: "Reescritura extrema con tono random (borracho, dramático, pirata, etc.)"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Translate to English",
                promptText: """
                    Translate the transcript to natural, fluent English. Preserve the speaker's tone and intent.
                    - If the transcript is already in English, return it as-is (with light cleanup of fillers).
                    - Adapt cultural references when needed (e.g. "che" → "hey", "boludo" → "dude" / "buddy").
                    - Keep all names, dates, numbers exactly as in the original.
                    - Output only the translated text. No notes, no markdown, no "Translation:" prefix.
                    """,
                icon: "globe.americas.fill",
                description: "Translate any dictation to English"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Traducir a español",
                promptText: """
                    Traducí el transcript a español natural y fluido (rioplatense preferido). Conservá el tono y la intención del hablante.
                    - Si el transcript ya está en español, devolvelo como está (con limpieza leve de muletillas).
                    - Adaptá referencias culturales cuando corresponda (ej. "dude" → "amigo", "OMG" → "Dios mío").
                    - Mantené nombres, fechas, números exactamente como en el original.
                    - Devolvé solo el texto traducido. Sin notas, sin markdown, sin prefijo "Traducción:".
                    """,
                icon: "globe.americas.fill",
                description: "Translates any dictation to Spanish (rioplatense)"
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
                    CRÍTICO: NUNCA borres palabras, oraciones ni ideas del dictado. Conservá TODO el contenido. El objetivo es limpieza mínima, no reescritura.

                    Qué hacer:
                    - Corregí SOLO puntuación (comas, puntos, signos de pregunta/exclamación, mayúsculas).
                    - Normalizá ortografía y tildes — sin cambiar las palabras que eligió el hablante.
                    - Colapsá SOLO tartamudeos obvios de transcripción (ej. "el-el-el coche" → "el coche"). Si el hablante repitió a propósito para enfatizar, MANTENÉ la repetición.
                    - Si el hablante dictó números como cifras ("5"), mantenelos como cifras. Si dijo la palabra ("cinco"), mantené la palabra.
                    - Si el hablante mezcla idiomas (ej. español con palabras en inglés como "download", "meeting", "deploy", "frontend", "bug"), MANTENÉ las palabras exactas como las dictó — no traduzcas.
                    - Insertá saltos de línea solo si el hablante dijo explícitamente "nueva línea" o "nuevo párrafo".

                    Qué NO hacer:
                    - NO borres muletillas ("eh", "em", "este", "o sea", "viste", "digamos"). Son parte natural del habla y el usuario las quiere conservadas.
                    - NO colapses repeticiones intencionales.
                    - NO "arregles" autocorrecciones borrando la primera versión. Si dijo "voy mañana, no, en realidad el jueves", dejalo tal cual.
                    - NO agregues listas, bullets, encabezados ni ningún formato que el hablante no pidió.
                    - NO agregues saludos, despedidas ni resúmenes.
                    - NO reformules, parafrasees ni "mejores" las palabras del hablante.
                    """,
                icon: "checkmark.seal.fill",
                description: "Limpieza mínima: corrige puntuación, preserva todo lo demás"
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
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Formal",
                promptText: """
                    - Reescribí en registro profesional y formal, apto para contratos, documentos legales y comunicación de negocios.
                    - Oraciones completas, vocabulario preciso, sin contracciones, sin jerga, sin muletillas.
                    - Preferí voz activa cuando suene natural; pasiva solo si el dictado claramente la pide.
                    - Corregí gramática y puntuación; colapsá repeticiones; mantené exactos todos los datos: nombres, fechas, montos.
                    - Números como cifras (5, no "cinco"); aclará abreviaturas la primera vez si pueden ser ambiguas.
                    - Organizá en párrafos de 2–4 oraciones. No agregues saludos ni cierres.
                    - No inventes contenido que no esté en el dictado.
                    """,
                icon: "briefcase.fill",
                description: "Tono formal y profesional para docs legales y negocios"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Coding",
                promptText: """
                    - Convertí el dictado en texto listo para código.
                    - Envolvé identificadores, nombres de funciones, paths, flags y comandos con backticks.
                    - Formateá bloques de código con triple backtick cuando el hablante dicte más de una línea; inferí el lenguaje si es obvio, si no dejalo en blanco.
                    - Convenciones de nombres: camelCase para variables/funciones, PascalCase para tipos, kebab-case para flags de CLI, SCREAMING_SNAKE para constantes.
                    - Símbolos dictados se convierten en puntuación: "abre paréntesis" → `(`, "igual" → `=`, "flecha" → `->`, "nueva línea" inserta salto.
                    - Prosa fuera de los bloques: corta y directa. Sin muletillas, sin repeticiones.
                    - No inventes código: solo lo que el hablante dictó.
                    """,
                icon: "terminal.fill",
                description: "Voz a código con backticks, identificadores y convenciones"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Summary",
                promptText: """
                    - Condensá el dictado en un resumen ejecutivo: 3 a 5 bullets accionables.
                    - Cada bullet arranca con un verbo y plantea una acción, decisión o hallazgo concreto.
                    - Sacá relleno, anécdotas y comentarios laterales; dejá solo lo que importa para tomar una decisión.
                    - Conservá todos los datos clave: nombres, fechas, cifras, deadlines, responsables.
                    - Números como cifras; formato consistente para fechas y montos.
                    - Sin saludos, sin cierres, sin preámbulo — solo los bullets.
                    - No inventes contenido que no esté en el dictado.
                    """,
                icon: "list.clipboard.fill",
                description: "Transforma un dictado largo en 3–5 bullets accionables"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Fun",
                promptText: """
                    Reescribí el transcript con un tono EXTREMADAMENTE divertido y exagerado. Elegí UN estilo absurdo al azar para cada request — no siempre el mismo. Estilos posibles (rotá):
                    - Borracho/mamado contando una historia: divagante, con tangentes random, "este... eh... bueno...".
                    - Narrador sobredramático: voz de trailer de película, todo es épico.
                    - Pibe de 12 años emocionado: re energético, exageraciones, "literal", "wacho".
                    - Amigo sarcástico: humor seco, comentarios irónicos al pasar.
                    - Pirata / gaucho / bardo medieval: elegí una personalidad y mantenela.

                    Reglas duras:
                    - Mantené todos los datos, nombres, fechas, números EXACTOS como se dictaron. No cambies QUÉ se dijo, solo CÓMO.
                    - No inventes contenido nuevo — adorná lo que ya está.
                    - Que se lea (sin muros de mayúsculas, máximo 2 signos de exclamación en todo el texto).
                    - 1-3 emojis OK si encajan con el personaje (cerveza 🍺 para borracho, espada ⚔️ para pirata, etc).
                    - Mantenete cerca del largo original — no te extiendas eternamente.
                    - Números como cifras.
                    """,
                icon: "face.smiling.fill",
                description: "Reescritura extrema con tono random (borracho, dramático, pirata, etc.)"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Translate to English",
                promptText: """
                    Translate the transcript to natural, fluent English. Preserve the speaker's tone and intent.
                    - If the transcript is already in English, return it as-is (with light cleanup of fillers).
                    - Adapt cultural references when needed (e.g. "che" → "hey", "boludo" → "dude" / "buddy").
                    - Keep all names, dates, numbers exactly as in the original.
                    - Output only the translated text. No notes, no markdown, no "Translation:" prefix.
                    """,
                icon: "globe.americas.fill",
                description: "Traducí cualquier dictado al inglés"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Traducir a español",
                promptText: """
                    Traducí el transcript a español natural y fluido (rioplatense preferido). Conservá el tono y la intención del hablante.
                    - Si el transcript ya está en español, devolvelo como está (con limpieza leve de muletillas).
                    - Adaptá referencias culturales cuando corresponda (ej. "dude" → "amigo", "OMG" → "Dios mío").
                    - Mantené nombres, fechas, números exactamente como en el original.
                    - Devolvé solo el texto traducido. Sin notas, sin markdown, sin prefijo "Traducción:".
                    """,
                icon: "globe.americas.fill",
                description: "Traducí cualquier dictado al español (rioplatense)"
            )
        ]
    }
}
