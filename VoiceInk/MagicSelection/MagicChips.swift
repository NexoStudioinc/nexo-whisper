import Foundation
import NaturalLanguage

/// Un chip de acción del panel Magic. Puede ser built-in (los que vienen de
/// fábrica) o custom (creado por el usuario: nombre + ícono + prompt). Todos se
/// pueden ocultar y reordenar desde Settings.
///
/// El chip de traducción (`isTranslate`) es especial: su comando se arma
/// dinámicamente con el idioma destino (preferido / detectado / elegido en el
/// submenú), ver `MagicTranslation`.
struct MagicChip: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var systemImage: String
    var command: String
    var enabled: Bool = true
    var isCustom: Bool = false
    var isTranslate: Bool = false
}

/// Store observable de los chips. Persiste en UserDefaults (JSON). Si no hay
/// nada guardado, arranca con los defaults. Compartido entre el panel y Settings.
@MainActor
final class MagicChipStore: ObservableObject {
    static let shared = MagicChipStore()

    @Published var chips: [MagicChip] = []

    private let key = "magicSelection.chips.v1"

    init() { load() }

    /// Solo los habilitados, en orden — lo que muestra el panel.
    var enabledChips: [MagicChip] { chips.filter { $0.enabled } }

    func toggle(_ chip: MagicChip) {
        guard let i = chips.firstIndex(where: { $0.id == chip.id }) else { return }
        chips[i].enabled.toggle()
        save()
    }

    func add(_ chip: MagicChip) { chips.append(chip); save() }

    func update(_ chip: MagicChip) {
        guard let i = chips.firstIndex(where: { $0.id == chip.id }) else { return }
        chips[i] = chip
        save()
    }

    func remove(_ chip: MagicChip) {
        chips.removeAll { $0.id == chip.id }
        save()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        chips.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func resetToDefaults() { chips = Self.defaults; save() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([MagicChip].self, from: data),
           !decoded.isEmpty {
            chips = decoded
            migrateLegacyBuiltins()
            mergeNewBuiltins()
        } else {
            chips = Self.defaults
        }
    }

    /// Migra los chips de fábrica guardados con títulos/comandos en español
    /// (versiones previas a la internacionalización) a las claves en inglés.
    /// Así el título se localiza en runtime (NSLocalizedString) y muestra el
    /// idioma correcto. No toca los chips custom ni el orden ni el on/off.
    private func migrateLegacyBuiltins() {
        let legacy = ["Explicar": "Explain", "Reescribir": "Rewrite",
                      "Resumir": "Summarize", "Traducir": "Translate",
                      "Sinónimos": "Synonyms", "Responder": "Reply",
                      "Ortografía": "Spelling", "Código": "Code"]
        var changed = false
        for i in chips.indices where !chips[i].isCustom {
            if let en = legacy[chips[i].title],
               let def = Self.defaults.first(where: { $0.title == en }) {
                let wasEnabled = chips[i].enabled
                chips[i].title = def.title
                chips[i].systemImage = def.systemImage
                chips[i].command = def.command
                chips[i].isTranslate = def.isTranslate
                chips[i].enabled = wasEnabled
                changed = true
            }
        }
        if changed { save() }
    }

    /// Agrega los chips de fábrica nuevos (que no estaban cuando el usuario
    /// guardó su config) sin pisar su orden ni sus chips custom. Así una nueva
    /// versión con chips nuevos los muestra sin que el usuario haga "Restaurar".
    private func mergeNewBuiltins() {
        let existing = Set(chips.map { $0.title.lowercased() })
        let missing = Self.defaults.filter { !existing.contains($0.title.lowercased()) }
        if !missing.isEmpty {
            chips.append(contentsOf: missing)
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(chips) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Los 8 chips de fábrica. El `title` es la clave en inglés (se localiza en
    /// runtime vía NSLocalizedString); el `command` va al LLM en inglés (mejor
    /// adherencia; el modelo responde en el idioma del texto del usuario).
    static var defaults: [MagicChip] {
        [
            MagicChip(title: "Explain", systemImage: "lightbulb",
                      command: "Explain this text clearly and simply."),
            MagicChip(title: "Rewrite", systemImage: "pencil.and.scribble",
                      command: "Rewrite this text so it is clearer and more polished. Return only the rewritten version."),
            MagicChip(title: "Summarize", systemImage: "text.alignleft",
                      command: "Summarize this text into its most important points."),
            MagicChip(title: "Translate", systemImage: "globe", command: "", isTranslate: true),
            MagicChip(title: "Synonyms", systemImage: "textformat.abc",
                      command: "Give me synonyms and alternatives for this."),
            MagicChip(title: "Reply", systemImage: "arrowshape.turn.up.left",
                      command: "Draft a short, useful reply to this, keeping the tone."),
            MagicChip(title: "Spelling", systemImage: "text.badge.checkmark",
                      command: "Fix the spelling and grammar. Return only the corrected text."),
            MagicChip(title: "Code", systemImage: "chevron.left.forwardslash.chevron.right",
                      command: "Analyze this code: find errors or bugs, briefly explain the problem, and return the corrected code in a markdown code block (```), indicating the language.")
        ]
    }
}

/// Lógica del chip "Traducir": idioma preferido (Settings), auto-detección del
/// idioma destino según el texto, y comando final. Flujo híbrido:
/// - click en el chip → traduce al destino resuelto (preferido o auto).
/// - submenú del chip → traduce al idioma elegido esa vez.
enum MagicTranslation {
    private static let prefKey = "magicSelection.translateLanguage"
    private static let autoKey = "magicSelection.translateAutoDetect"

    /// Idiomas ofrecidos en el submenú / picker de Settings. Claves en inglés
    /// (se localizan al mostrarse vía NSLocalizedString) y se usan tal cual en
    /// el comando que va al LLM.
    static let languages = [
        "English", "Spanish", "Portuguese", "French", "Italian", "German",
        "Japanese", "Chinese", "Korean", "Russian", "Arabic", "Hindi", "Dutch", "Catalan"
    ]

    /// Idioma de traducción preferido (default: English).
    static var preferredLanguage: String {
        get { UserDefaults.standard.string(forKey: prefKey) ?? "English" }
        set { UserDefaults.standard.set(newValue, forKey: prefKey) }
    }

    /// ¿Detectar automáticamente el idioma destino según el texto? (default sí.)
    static var autoDetect: Bool {
        get { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }

    /// Nombre del idioma del sistema en inglés canónico (ej. "Spanish"), para
    /// que coincida con `languages` y con el comando que va al LLM.
    static var systemLanguageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? "es"
        let name = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "Spanish"
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Construye el comando de traducción. `override` fuerza un idioma puntual
    /// (submenú); si es nil, resuelve el destino (auto o preferido).
    static func command(for text: String, override: String? = nil) -> String {
        let target = override ?? resolveTarget(for: text)
        return "Translate this text to \(target). Return ONLY the translation, no notes."
    }

    /// Resuelve el idioma destino. Con auto-detección: si el texto YA está en el
    /// idioma preferido, traduce al del sistema; si está en otro, al preferido.
    /// Así "Traducir" siempre hace algo útil sin que elijas.
    private static func resolveTarget(for text: String) -> String {
        guard autoDetect else { return preferredLanguage }
        guard let detected = detectedLanguageName(text) else { return preferredLanguage }
        if detected.caseInsensitiveCompare(preferredLanguage) == .orderedSame {
            // El texto ya está en el preferido → traducir al idioma del usuario.
            let sys = systemLanguageName
            return sys.caseInsensitiveCompare(preferredLanguage) == .orderedSame ? "English" : sys
        }
        return preferredLanguage
    }

    /// Detecta el idioma dominante del texto con NaturalLanguage (on-device).
    /// Devuelve el nombre en inglés canónico para comparar con `preferredLanguage`.
    private static func detectedLanguageName(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }
        let name = Locale(identifier: "en").localizedString(forLanguageCode: lang.rawValue)
        return name.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}
