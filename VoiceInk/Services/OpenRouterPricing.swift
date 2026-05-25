import Foundation
import OSLog

/// Fetch de precios reales por modelo desde OpenRouter (`/api/v1/models`).
///
/// OpenRouter expone una lista pública de modelos con sus precios reales
/// por 1k tokens, sin requerir API key. Cacheamos 24h en UserDefaults para
/// evitar requests innecesarios. Si está offline, usamos la tabla
/// hardcoded de `TokenPricing` como fallback.
///
/// Endpoint: <https://openrouter.ai/api/v1/models>
/// Schema relevante:
/// ```json
/// {
///   "data": [
///     { "id": "openai/gpt-4o-mini", "pricing": { "prompt": "0.00000015", "completion": "0.0000006" } },
///     ...
///   ]
/// }
/// ```
/// Los valores son USD por TOKEN (no por 1k). Multiplicamos por 1000 al
/// guardar para mantener consistencia con `TokenPricing.Price`.
@MainActor
final class OpenRouterPricing: ObservableObject {
    static let shared = OpenRouterPricing()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "OpenRouterPricing")
    private let cacheKey = "openRouterPricingCache"
    private let cacheTimestampKey = "openRouterPricingTimestamp"
    private let cacheTTL: TimeInterval = 24 * 60 * 60  // 24h

    /// `[modelKey: (input USD/1k, output USD/1k)]`
    @Published private(set) var prices: [String: TokenPricing.Price] = [:]

    private init() {
        loadCache()
    }

    /// Devuelve precio para `provider`/`model` si está en cache. Si no,
    /// el caller cae al lookup hardcoded.
    func price(provider: String, model: String) -> TokenPricing.Price? {
        // OpenRouter usa keys tipo "openai/gpt-4o-mini". Probamos varios
        // formatos de match.
        let normalized = model.lowercased()
        let providerKey = provider.lowercased()
        let candidates = [
            "\(providerKey)/\(normalized)",
            normalized
        ]
        for key in candidates {
            if let p = prices[key] { return p }
        }
        // Match parcial: cualquier key que contenga el modelo.
        return prices.first { $0.key.hasSuffix("/\(normalized)") || $0.key == normalized }?.value
    }

    /// Refresca el cache si está vencido. No-blocking. Errores silenciosos.
    func refreshIfNeeded() {
        let ts = UserDefaults.standard.double(forKey: cacheTimestampKey)
        let age = Date().timeIntervalSince1970 - ts
        guard age > cacheTTL || prices.isEmpty else {
            logger.debug("Pricing cache fresh (\(Int(age))s old), skip fetch")
            return
        }
        Task { await fetch() }
    }

    // MARK: - Private

    private func fetch() async {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.notice("OpenRouter fetch returned non-200, skipping")
                return
            }
            let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            var newPrices: [String: TokenPricing.Price] = [:]
            for model in decoded.data {
                let inputPerToken = Double(model.pricing.prompt) ?? 0
                let outputPerToken = Double(model.pricing.completion) ?? 0
                if inputPerToken > 0 || outputPerToken > 0 {
                    newPrices[model.id.lowercased()] = (inputPerToken * 1000, outputPerToken * 1000)
                }
            }
            self.prices = newPrices
            saveCache()
            logger.notice("OpenRouter pricing refreshed: \(newPrices.count, privacy: .public) models")
        } catch {
            logger.notice("OpenRouter fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: PriceDTO].self, from: data) else {
            return
        }
        prices = decoded.mapValues { ($0.input, $0.output) }
    }

    private func saveCache() {
        let dto = prices.mapValues { PriceDTO(input: $0.input, output: $0.output) }
        if let data = try? JSONEncoder().encode(dto) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
        }
    }

    // MARK: - DTOs

    private struct OpenRouterResponse: Decodable {
        let data: [Model]
        struct Model: Decodable {
            let id: String
            let pricing: Pricing
        }
        struct Pricing: Decodable {
            let prompt: String
            let completion: String
        }
    }

    private struct PriceDTO: Codable {
        let input: Double
        let output: Double
    }
}
