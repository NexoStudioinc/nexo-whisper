import Foundation
import AppKit
import SwiftData
import OSLog

/// Detecta palabras "raras" en las transcripciones del usuario para
/// sugerirlas al diccionario de Nexo Whisper.
///
/// Heurística simple:
/// 1. Tokeniza el texto, lower-case, solo letras (descarta números/símbolos).
/// 2. Filtra palabras cortas (≤ 3 chars).
/// 3. Marca como "rara" si está mal escrita según `NSSpellChecker` y no
///    aparece ya en el vocabulario del usuario.
/// 4. Cuenta apariciones. Al cruzar `suggestionThreshold` (3 por default)
///    aparece en `pendingSuggestions` para mostrar en la UI.
///
/// El usuario puede:
/// - **Aceptar** → se inserta como `VocabularyWord`, se borra el contador.
/// - **Rechazar** → entra a `rejectedWords`, no se vuelve a sugerir.
/// - **Ignorar por ahora** → queda con su count actual.
///
/// Persistencia: UserDefaults. Los datos son pocos (palabras y un Int por
/// cada una) así que no justifica SwiftData.
@MainActor
final class RareWordTracker: ObservableObject {
    static let shared = RareWordTracker()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RareWordTracker")
    private let countsKey = "rareWordCounts"
    private let rejectedKey = "rareWordRejected"
    private let suggestionThreshold = 3

    @Published private(set) var pendingSuggestions: [String] = []

    private var counts: [String: Int] {
        didSet {
            UserDefaults.standard.set(counts, forKey: countsKey)
            refreshPending()
        }
    }

    private var rejected: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(rejected), forKey: rejectedKey)
        }
    }

    private init() {
        self.counts = (UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
        self.rejected = Set((UserDefaults.standard.array(forKey: rejectedKey) as? [String]) ?? [])
        refreshPending()
    }

    /// Procesa un texto recién transcrito. Llamar después de que la
    /// transcripción se haya guardado en SwiftData. Es no-bloqueante.
    func feed(text: String, modelContext: ModelContext) {
        guard !text.isEmpty else { return }

        // Vocabulario actual del usuario (palabras ya conocidas).
        let userVocabulary: Set<String> = {
            let fetch = FetchDescriptor<VocabularyWord>()
            let items = (try? modelContext.fetch(fetch)) ?? []
            return Set(items.map { $0.word.lowercased() })
        }()

        let checker = NSSpellChecker.shared
        // Idioma del spellchecker: usar el del usuario, no el primer
        // disponible del sistema (que suele ser "en" y da falsos positivos
        // para palabras en español). Fallback al idioma actual de la app.
        let appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        let language: String = {
            let candidate = appLanguage == "es" ? "es" : appLanguage
            return checker.availableLanguages.contains(candidate) ? candidate : (checker.availableLanguages.first ?? "en")
        }()

        let tokens = tokenize(text)
        var newCounts = counts
        for token in tokens {
            // Filtros rápidos
            if token.count <= 3 { continue }
            if rejected.contains(token) { continue }
            if userVocabulary.contains(token) { continue }

            // Spell-check: si la palabra está bien escrita en el idioma del
            // sistema, no la consideramos rara.
            let range = checker.checkSpelling(of: token, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            if range.location == NSNotFound { continue }

            newCounts[token, default: 0] += 1
        }

        if newCounts != counts {
            counts = newCounts
        }
    }

    /// El usuario aceptó la sugerencia → la sumamos al vocabulario y
    /// limpiamos el contador. Devuelve `true` si la inserción fue exitosa.
    @discardableResult
    func accept(word: String, modelContext: ModelContext) -> Bool {
        let new = VocabularyWord(word: word)
        modelContext.insert(new)
        do {
            try modelContext.save()
            counts.removeValue(forKey: word.lowercased())
            return true
        } catch {
            logger.error("Failed to add suggested word: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// El usuario rechazó la sugerencia → no se vuelve a ofrecer.
    func reject(word: String) {
        rejected.insert(word.lowercased())
        counts.removeValue(forKey: word.lowercased())
    }

    /// El usuario decide ignorar por ahora — la sugerencia desaparece pero
    /// puede volver a aparecer si la palabra se sigue diciendo.
    func dismiss(word: String) {
        counts.removeValue(forKey: word.lowercased())
    }

    // MARK: - Helpers

    private func tokenize(_ text: String) -> [String] {
        let allowed = CharacterSet.letters
        return text
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
    }

    private func refreshPending() {
        pendingSuggestions = counts
            .filter { $0.value >= suggestionThreshold }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
}
