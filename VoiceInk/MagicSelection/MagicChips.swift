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
            mergeNewBuiltins()
        } else {
            chips = Self.defaults
        }
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

    /// Los 7 chips de fábrica (en español rioplatense).
    static var defaults: [MagicChip] {
        [
            MagicChip(title: "Explicar", systemImage: "lightbulb",
                      command: "Explicá este texto de forma clara y simple."),
            MagicChip(title: "Reescribir", systemImage: "pencil.and.scribble",
                      command: "Reescribí este texto para que quede más claro y pulido. Devolvé solo la versión reescrita."),
            MagicChip(title: "Resumir", systemImage: "text.alignleft",
                      command: "Resumí este texto en los puntos más importantes."),
            MagicChip(title: "Traducir", systemImage: "globe", command: "", isTranslate: true),
            MagicChip(title: "Sinónimos", systemImage: "textformat.abc",
                      command: "Dame sinónimos y variantes de esto."),
            MagicChip(title: "Responder", systemImage: "arrowshape.turn.up.left",
                      command: "Redactá una respuesta breve y útil a esto, manteniendo el tono."),
            MagicChip(title: "Ortografía", systemImage: "text.badge.checkmark",
                      command: "Corregí la ortografía y la gramática. Devolvé solo el texto corregido."),
            MagicChip(title: "Código", systemImage: "chevron.left.forwardslash.chevron.right",
                      command: "Analizá este código: detectá errores o bugs, explicá brevemente el problema y devolvé el código corregido en un bloque de código markdown (```), indicando el lenguaje.")
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

    /// Idiomas ofrecidos en el submenú / picker de Settings.
    static let languages = [
        "Inglés", "Español", "Portugués", "Francés", "Italiano", "Alemán",
        "Japonés", "Chino", "Coreano", "Ruso", "Árabe", "Hindi", "Holandés", "Catalán"
    ]

    /// Idioma de traducción preferido (default: Inglés).
    static var preferredLanguage: String {
        get { UserDefaults.standard.string(forKey: prefKey) ?? "Inglés" }
        set { UserDefaults.standard.set(newValue, forKey: prefKey) }
    }

    /// ¿Detectar automáticamente el idioma destino según el texto? (default sí.)
    static var autoDetect: Bool {
        get { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }

    /// Nombre del idioma del sistema (ej. "Español"), capitalizado.
    static var systemLanguageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? "es"
        let name = Locale.current.localizedString(forLanguageCode: code) ?? "Español"
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Construye el comando de traducción. `override` fuerza un idioma puntual
    /// (submenú); si es nil, resuelve el destino (auto o preferido).
    static func command(for text: String, override: String? = nil) -> String {
        let target = override ?? resolveTarget(for: text)
        return "Traducí este texto al \(target). Devolvé SOLO la traducción, sin notas."
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
            return sys.caseInsensitiveCompare(preferredLanguage) == .orderedSame ? "Inglés" : sys
        }
        return preferredLanguage
    }

    /// Detecta el idioma dominante del texto con NaturalLanguage (on-device).
    private static func detectedLanguageName(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }
        let name = Locale.current.localizedString(forLanguageCode: lang.rawValue)
        return name.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}
