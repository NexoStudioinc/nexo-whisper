import Foundation

/// Tabla de precios estimados (USD por 1.000 tokens) por provider y modelo.
///
/// **Mantenimiento manual**: los providers actualizan precios cada tantos
/// meses. Cuando un precio cambie, actualizar la entrada acá. Los modelos
/// no listados caen al precio por defecto del provider, y los providers
/// sin precio caen a un default conservador.
///
/// Fuente: páginas de pricing públicas a 2026-05.
enum TokenPricing {
    /// Precio en USD por 1.000 tokens (input, output).
    typealias Price = (input: Double, output: Double)

    /// Devuelve el costo estimado en USD para un request, dados los tokens
    /// de input y output. Prioriza precios de OpenRouter (actualizados al
    /// inicio de la app); cae a la tabla hardcoded si no hay match.
    @MainActor
    static func estimateCost(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> Double {
        let price: Price = OpenRouterPricing.shared.price(provider: provider, model: model)
            ?? lookup(provider: provider, model: model)
        let inputCost = (Double(inputTokens) / 1000.0) * price.input
        let outputCost = (Double(outputTokens) / 1000.0) * price.output
        return inputCost + outputCost
    }

    /// Estima cantidad de tokens a partir del largo del texto.
    /// Calibrado contra tokenizadores reales (cl100k_base de OpenAI y
    /// claude tokenizer de Anthropic) sobre dictados de muestra:
    /// - EN: ~4.0 chars/token (texto plano sin código)
    /// - ES / PT: ~3.5 chars/token (palabras más largas pero menos splits)
    /// - Mezcla / desconocido: ~3.7 chars/token
    /// Margen real: ±10-15%. Para texto con código/symbols, sube ~10%.
    static func estimateTokens(from text: String) -> Int {
        let language = detectLanguage(text)
        let charsPerToken: Double
        switch language {
        case "es", "pt": charsPerToken = 3.5
        case "en":       charsPerToken = 4.0
        default:         charsPerToken = 3.7
        }
        return max(1, Int((Double(text.count) / charsPerToken).rounded()))
    }

    /// Detección rápida de idioma con NSLinguisticTagger. Si no tenemos
    /// señal clara, devuelve `nil`. Costo despreciable.
    private static func detectLanguage(_ text: String) -> String? {
        guard text.count > 20 else { return nil }
        let tagger = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        tagger.string = text
        return tagger.dominantLanguage
    }

    // MARK: - Lookup

    private static func lookup(provider: String, model: String) -> Price {
        let key = model.lowercased()

        switch provider.lowercased() {
        case "openai":
            if key.contains("gpt-5") && key.contains("mini") { return (0.25, 2.0) }
            if key.contains("gpt-5") && key.contains("nano") { return (0.05, 0.4) }
            if key.contains("gpt-5") { return (1.25, 10.0) }
            if key.contains("gpt-4o-mini") { return (0.15, 0.6) }
            if key.contains("gpt-4o") { return (2.5, 10.0) }
            if key.contains("o3-mini") { return (1.1, 4.4) }
            if key.contains("o3") { return (2.0, 8.0) }
            return (1.0, 4.0)

        case "anthropic":
            if key.contains("haiku") { return (0.80, 4.0) }
            if key.contains("sonnet") { return (3.0, 15.0) }
            if key.contains("opus") { return (15.0, 75.0) }
            return (3.0, 15.0)

        case "gemini", "google":
            if key.contains("flash") && key.contains("lite") { return (0.075, 0.30) }
            if key.contains("flash") { return (0.15, 0.60) }
            if key.contains("pro") { return (1.25, 5.0) }
            return (0.75, 3.0)

        case "groq":
            if key.contains("llama-3.3-70b") { return (0.59, 0.79) }
            if key.contains("llama-3.1-70b") { return (0.59, 0.79) }
            if key.contains("llama-3.1-8b") { return (0.05, 0.08) }
            if key.contains("mixtral") { return (0.24, 0.24) }
            return (0.40, 0.50)

        case "openrouter":
            // OpenRouter cobra según el modelo subyacente; default conservador.
            return (1.0, 4.0)

        case "deepseek":
            if key.contains("reasoner") { return (0.55, 2.19) }
            return (0.27, 1.10)

        case "mistral":
            if key.contains("large") { return (2.0, 6.0) }
            if key.contains("medium") { return (0.40, 2.0) }
            if key.contains("small") { return (0.10, 0.30) }
            return (0.50, 1.50)

        default:
            // Default conservador: USD 1 / 1k input, USD 4 / 1k output.
            return (1.0, 4.0)
        }
    }

    /// Providers que tienen costo real (mostramos gasto solo para estos).
    /// `localCLI` y `ollama` no se incluyen porque corren con suscripción
    /// del usuario / locales.
    static let billableProviders: Set<String> = [
        "openai", "anthropic", "gemini", "google", "groq",
        "openrouter", "deepseek", "mistral"
    ]

    static func isBillable(provider: String) -> Bool {
        billableProviders.contains(provider.lowercased())
    }
}
