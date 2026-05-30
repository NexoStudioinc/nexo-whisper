import Foundation
import OSLog

/// Cliente de streaming propio para Magic Selection. Inspirado en el
/// `LLMClient.streamCompletion` de Hover (GPL-3.0), pero reescrito y ampliado:
/// soporta DOS familias de SSE (OpenAI-compatible y Anthropic) en vez de una
/// sola, y no toca la librería externa LLMkit (que hoy solo streamea audio,
/// no chat). Así sumamos tokens en vivo sin reescribir el motor de IA ni
/// quedar atados a un cambio de dependencia.
///
/// Devuelve un `AsyncThrowingStream<String, Error>` que emite los fragmentos
/// de texto (tokens) a medida que llegan. El parseo del header de control y la
/// lógica de Magic viven una capa arriba (`AIEnhancementService`).
/// Qué decidió la IA hacer con el resultado.
enum MagicControl: Equatable {
    /// Reemplazar la selección con el texto.
    case replace
    /// Mostrar el texto en el panel (pregunta/info). `imageQuery` opcional.
    case answer(imageQuery: String?)
    /// Ejecutar una acción del sistema (Notas, Mail, Recordatorios). El texto
    /// que sigue es el contenido (cuerpo de la nota/mail/recordatorio).
    case action(tool: String, params: [String: String])
}

/// Evento de alto nivel del pipeline de Magic en streaming. Primero llega el
/// `control` (qué hacer), después los `token` de texto en vivo.
enum MagicStreamEvent {
    case control(MagicControl)
    case token(String)
}

enum MagicStreamingClient {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicStreamingClient"
    )

    /// Familia de protocolo de streaming según el provider.
    enum Family {
        /// SSE estilo OpenAI: `data: {"choices":[{"delta":{"content":"…"}}]}`,
        /// termina con `data: [DONE]`. Cubre OpenAI, Groq, Cerebras, Gemini
        /// (endpoint OpenAI), OpenRouter, Mistral, Custom y Ollama (vía /v1).
        case openAICompatible
        /// SSE estilo Anthropic: eventos `content_block_delta` con
        /// `delta.text`. Header `x-api-key` + `anthropic-version`.
        case anthropic
    }

    struct Config {
        let family: Family
        /// URL completa del endpoint de chat (ya con el path correcto).
        let url: URL
        let apiKey: String
        let model: String
        let systemPrompt: String
        let userMessage: String
        /// Turnos previos de la conversación (para re-preguntas en el panel).
        /// Cada par es (pregunta del usuario, respuesta del asistente).
        let history: [(user: String, assistant: String)]
        var maxTokens: Int = 4096
        var temperature: Double = 0.3
        var timeout: TimeInterval = 60
    }

    /// Errores propios (se mapean a un fallback no-streaming si hace falta).
    enum StreamError: Error {
        case invalidResponse
        case httpStatus(Int)
        case notStreamable
    }

    // MARK: - Stream

    static func stream(_ config: Config) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(config)
                    let session = URLSession(configuration: .ephemeral)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw StreamError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        logger.error("Streaming HTTP \(http.statusCode)")
                        throw StreamError.httpStatus(http.statusCode)
                    }

                    for try await rawLine in bytes.lines {
                        try Task.checkCancellation()
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard line.hasPrefix("data:") else { continue }

                        let payload = line.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        guard let data = payload.data(using: .utf8) else { continue }

                        if let token = parseToken(data, family: config.family) {
                            if !token.isEmpty { continuation.yield(token) }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    private static func makeRequest(_ config: Config) throws -> URLRequest {
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        switch config.family {
        case .anthropic:
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var messages = config.history.flatMap { turn in
                [["role": "user", "content": turn.user],
                 ["role": "assistant", "content": turn.assistant]]
            }
            messages.append(["role": "user", "content": config.userMessage])
            body = [
                "model": config.model,
                "max_tokens": config.maxTokens,
                "system": config.systemPrompt,
                "messages": messages,
                "stream": true
            ]
        case .openAICompatible:
            if !config.apiKey.isEmpty {
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            }
            var messages: [[String: String]] = [["role": "system", "content": config.systemPrompt]]
            for turn in config.history {
                messages.append(["role": "user", "content": turn.user])
                messages.append(["role": "assistant", "content": turn.assistant])
            }
            messages.append(["role": "user", "content": config.userMessage])
            body = [
                "model": config.model,
                "messages": messages,
                "temperature": config.temperature,
                "stream": true
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - SSE token parsing

    /// Extrae el fragmento de texto de un chunk SSE según la familia. Tolerante:
    /// si el JSON no tiene el campo esperado, devuelve nil (se ignora la línea).
    private static func parseToken(_ data: Data, family: Family) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        switch family {
        case .openAICompatible:
            // {"choices":[{"delta":{"content":"…"}}]}
            guard let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                return nil
            }
            return content
        case .anthropic:
            // {"type":"content_block_delta","delta":{"type":"text_delta","text":"…"}}
            guard (obj["type"] as? String) == "content_block_delta",
                  let delta = obj["delta"] as? [String: Any],
                  let text = delta["text"] as? String else {
                return nil
            }
            return text
        }
    }
}
