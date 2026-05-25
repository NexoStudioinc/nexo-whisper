import Foundation

/// Registro estimado de uso de tokens por request a un provider API.
///
/// **Importante**: el costo es una *estimación*, no una factura real. Los
/// providers (OpenAI/Anthropic/etc) cobran sobre los tokens efectivos que
/// devuelve su tokenizador, no sobre `text.count / 3.5`.
///
/// **Por qué NO es @Model de SwiftData**: agregar un nuevo modelo a un
/// schema existente provocaba crashes de precondición (no atrapables con
/// try/catch) si la migración lightweight fallaba en runtime. Como el
/// volumen de datos es chico (un Int + un Double + 2 Strings cortos por
/// request) lo persistimos en UserDefaults como JSON desde
/// `TokenUsageStore`. Cero riesgo de crash.
struct TokenUsageRecord: Codable, Identifiable {
    var id: UUID
    var date: Date
    var provider: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double
    ) {
        self.id = id
        self.date = date
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }
}

/// Persistencia liviana en UserDefaults para los registros de uso.
/// Mantiene un máximo de `maxRecords` para no inflar UserDefaults.
@MainActor
final class TokenUsageStore: ObservableObject {
    static let shared = TokenUsageStore()

    private let key = "tokenUsageRecords"
    private let maxRecords = 5000  // ~6 meses de uso intensivo, sobra.

    @Published private(set) var records: [TokenUsageRecord] = []

    private init() {
        load()
    }

    func append(_ record: TokenUsageRecord) {
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        save()
    }

    /// Borra todos los registros. Pensado para cuando el usuario quiere
    /// arrancar el tracking de cero (ej: para validar contra la factura
    /// real del provider).
    func reset() {
        records = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TokenUsageRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
