import Foundation
import SwiftData
import AppKit
import os
import LLMkit

enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AIEnhancementService")

    @Published var isEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnhancementEnabled, forKey: "isAIEnhancementEnabled")
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.set(useClipboardContext, forKey: "useClipboardContext")
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.set(useScreenCaptureContext, forKey: "useScreenCaptureContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            }
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedPromptId?.uuidString, forKey: "selectedPromptId")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }

    var allPrompts: [CustomPrompt] {
        return customPrompts
    }

    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private var baseTimeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        return stored > 0 ? TimeInterval(stored) : 7
    }
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    @Published var lastCapturedClipboard: String?

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        self.isEnhancementEnabled = UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled")
        self.useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
        self.useScreenCaptureContext = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        if let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }

        if let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId") {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }

        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            self.selectedPromptId = allPrompts.first?.id
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        initializePredefinedPrompts()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService? {
        return aiService
    }

    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func getSystemMessage(for mode: EnhancementPrompt) async -> String {
        let selectedTextContext: String
        if AXIsProcessTrusted() {
            if let selectedText = await SelectedTextService.fetchSelectedText(), !selectedText.isEmpty {
                selectedTextContext = "\n\n<CURRENTLY_SELECTED_TEXT>\n\(selectedText)\n</CURRENTLY_SELECTED_TEXT>"
            } else {
                selectedTextContext = ""
            }
        } else {
            selectedTextContext = ""
        }

        let clipboardContext = if useClipboardContext,
                              let clipboardText = lastCapturedClipboard,
                              !clipboardText.isEmpty {
            "\n\n<CLIPBOARD_CONTEXT>\n\(clipboardText)\n</CLIPBOARD_CONTEXT>"
        } else {
            ""
        }

        let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            "\n\n<CURRENT_WINDOW_CONTEXT>\n\(capturedText)\n</CURRENT_WINDOW_CONTEXT>"
        } else {
            ""
        }

        let customVocabulary = customVocabularyService.getCustomVocabulary(from: modelContext)

        let allContextSections = selectedTextContext + clipboardContext + screenCaptureContext

        let customVocabularySection = if !customVocabulary.isEmpty {
            """


            The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
            <CUSTOM_VOCABULARY>
            \(customVocabulary)
            </CUSTOM_VOCABULARY>
            """
        } else {
            ""
        }

        let finalContextSection = allContextSections + customVocabularySection

        if let activePrompt = activePrompt {
            // El prompt "Assistant" se removió de los predefinidos. Si más
            // adelante volvemos a un prompt sin instrucciones de sistema,
            // se puede flaguear por `activePrompt.useSystemInstructions == false`.
            return activePrompt.finalPromptText + finalContextSection
        } else {
            let defaultPrompt = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId }) ?? allPrompts.first!
            return defaultPrompt.finalPromptText + finalContextSection
        }
    }

    private func makeRequest(text: String, mode: EnhancementPrompt) async throws -> String {
        guard isConfigured else {
            throw EnhancementError.notConfigured
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        let systemMessage = await getSystemMessage(for: mode)

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        return try await dispatchToProvider(systemMessage: systemMessage, userMessage: formattedText)
    }

    /// Envía un par (systemPrompt, userMessage) al provider AI activo y
    /// devuelve la respuesta ya filtrada. Centraliza el despacho por provider
    /// (Ollama / Local CLI / Anthropic / OpenAI-compatible) para que tanto el
    /// enhancement de transcripción como flujos especiales (Magic Selection)
    /// reusen exactamente la misma plomería y manejo de errores.
    private func dispatchToProvider(systemMessage: String, userMessage: String) async throws -> String {
        if aiService.selectedProvider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(
                    text: userMessage,
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalAIError {
                    switch localError {
                    case .timeout:
                        throw EnhancementError.timeout
                    default:
                        throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                    }
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .localCLI {
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: userMessage)
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalCLIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .apple {
            do {
                let result = try await AppleFoundationService.generate(instructions: systemMessage, prompt: userMessage)
                return AIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                throw EnhancementError.customError(error.localizedDescription)
            }
        }

        try await waitForRateLimit()

        do {
            let result: String
            switch aiService.selectedProvider {
            case .anthropic:
                result = try await AnthropicLLMClient.chatCompletion(
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(userMessage)],
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
            default:
                guard let baseURL = URL(string: aiService.selectedProvider.baseURL) else {
                    throw EnhancementError.customError("\(aiService.selectedProvider.rawValue) has an invalid API endpoint URL. Please update it in AI settings.")
                }
                let temperature = aiService.currentModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
                let reasoningEffort = ReasoningConfig.getReasoningParameter(
                    for: aiService.selectedProvider,
                    modelName: aiService.currentModel
                )
                let extraBody = ReasoningConfig.getExtraBodyParameters(
                    for: aiService.selectedProvider,
                    modelName: aiService.currentModel
                )
                result = try await OpenAILLMClient.chatCompletion(
                    baseURL: baseURL,
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(userMessage)],
                    systemPrompt: systemMessage,
                    temperature: temperature,
                    reasoningEffort: reasoningEffort,
                    extraBody: extraBody,
                    timeout: baseTimeout
                )
            }
            return AIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }
    }

    /// Pre-calienta el motor de IA si conviene, ANTES de mandar el comando.
    /// Pensado para llamarse apenas se activa Magic Selection (al hacer el
    /// wiggle), mientras el usuario todavía está dictando: el trabajo de
    /// arranque se solapa con el dictado y la respuesta llega más rápido.
    ///
    /// DETECCIÓN AUTOMÁTICA: solo hace algo con Local CLI (que paga cold start
    /// del proceso en cada pedido). Con providers de API remota no hace nada
    /// — no tienen ese costo y no queremos gastar de gusto. Debounced 30s.
    func prewarmForMagic() {
        guard aiService.selectedProvider == .localCLI else { return }
        aiService.prewarmActiveLocalCLI()
    }

    // MARK: - Magic Selection (streaming)

    /// Ejecuta un comando de Magic en STREAMING. Devuelve eventos: primero el
    /// `control` (replace/answer + imagen/acción), luego los `token` de texto en vivo.
    ///
    /// El modelo responde con una PRIMERA LÍNEA de control (`@@REPLACE@@` /
    /// `@@ANSWER@@` / `@@ANSWER|img=Entidad@@` / `@@ACTION|tool=…@@`) y debajo el
    /// texto plano, que sí streamea token a token.
    ///
    /// `history`: turnos previos (pregunta, respuesta) para re-preguntar en el
    /// panel sin re-seleccionar.
    ///
    /// Robustez: si el provider no streamea (Local CLI) o el stream falla antes
    /// de emitir nada, cae a `fallbackNonStreaming` (mismo prompt header vía
    /// `dispatchToProvider`) y emite el resultado completo de una. Así nunca se
    /// rompe lo que ya andaba.
    func runMagicCommandStreaming(
        selectedText: String,
        command: String,
        history: [(user: String, assistant: String)] = []
    ) -> AsyncThrowingStream<MagicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

                // Fallback no-streaming (Local CLI o error temprano): usa el MISMO
                // prompt de header, así las acciones y el formato funcionan igual
                // sin streaming. Pide la respuesta completa de una.
                func fallbackNonStreaming() async {
                    do {
                        let raw = try await self.dispatchToProvider(
                            systemMessage: Self.magicStreamingSystemPrompt,
                            userMessage: Self.magicUserMessage(selectedText: selectedText, command: trimmedCommand)
                        )
                        let (control, body) = Self.parseHeaderResponse(raw)
                        continuation.yield(.control(control))
                        continuation.yield(.token(body))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                // Gating BYOK Pro: tier free solo providers locales.
                guard self.isConfigured else { continuation.finish(throwing: EnhancementError.notConfigured); return }
                let provider = self.aiService.selectedProvider
                if provider.requiresBYOKLicense, !FeatureGate.isAvailable(.byokEnhancement) {
                    continuation.finish(throwing: EnhancementError.proBYOKRequired); return
                }
                guard !trimmedCommand.isEmpty else {
                    continuation.finish(throwing: EnhancementError.customError("No se entendió ningún comando de voz.")); return
                }

                // Provider sin streaming (Local CLI) → fallback directo.
                guard let cfg = self.makeMagicStreamConfig(selectedText: selectedText, command: trimmedCommand, history: history) else {
                    await fallbackNonStreaming()
                    return
                }

                var emittedControl = false
                var headerDone = false
                var buffer = ""

                do {
                    for try await chunk in MagicStreamingClient.stream(cfg) {
                        try Task.checkCancellation()
                        if headerDone {
                            continuation.yield(.token(chunk))
                            continue
                        }
                        buffer += chunk
                        if let nl = buffer.firstIndex(of: "\n") {
                            let header = String(buffer[..<nl])
                            let rest = String(buffer[buffer.index(after: nl)...])
                            continuation.yield(.control(Self.parseControlHeader(header)))
                            emittedControl = true
                            headerDone = true
                            if !rest.isEmpty { continuation.yield(.token(rest)) }
                        } else if buffer.count > 64 {
                            // No vino header: por seguridad tratamos todo como
                            // respuesta (no tocar el texto del usuario).
                            continuation.yield(.control(.answer(imageQuery: nil)))
                            emittedControl = true
                            headerDone = true
                            continuation.yield(.token(buffer))
                        }
                    }
                    if !headerDone {
                        // El stream terminó antes del salto de línea. Puede ser:
                        // (a) una ACCIÓN sin cuerpo (ej. @@ACTION|tool=maps|query=…@@,
                        //     que no lleva texto debajo) → parsear como control;
                        // (b) una respuesta corta sin header → mostrarla como texto.
                        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("@@") {
                            continuation.yield(.control(Self.parseControlHeader(trimmed)))
                        } else {
                            continuation.yield(.control(.answer(imageQuery: nil)))
                            if !buffer.isEmpty { continuation.yield(.token(buffer)) }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    // Si todavía no emitimos nada, reintentamos sin streaming.
                    if emittedControl {
                        continuation.finish(throwing: error)
                    } else {
                        await fallbackNonStreaming()
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Construye la config de streaming según el provider activo. Devuelve nil
    /// para providers que no soportan streaming de chat (Local CLI).
    private func makeMagicStreamConfig(
        selectedText: String,
        command: String,
        history: [(user: String, assistant: String)]
    ) -> MagicStreamingClient.Config? {
        let provider = aiService.selectedProvider
        let model = aiService.currentModel
        let apiKey = aiService.apiKey

        let family: MagicStreamingClient.Family
        let urlString: String
        switch provider {
        case .localCLI, .apple:
            return nil   // no streamean chat → fallback no-streaming (dispatchToProvider)
        case .anthropic:
            family = .anthropic
            urlString = "https://api.anthropic.com/v1/messages"
        case .ollama:
            // Ollama expone un endpoint OpenAI-compatible en /v1.
            let base = (provider.baseURL).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            family = .openAICompatible
            urlString = "\(base)/v1/chat/completions"
        default:
            // Resto de providers de texto: ya traen el path /chat/completions.
            family = .openAICompatible
            urlString = provider.baseURL
        }
        guard let url = URL(string: urlString), !urlString.isEmpty else { return nil }

        let temperature = model.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
        return MagicStreamingClient.Config(
            family: family,
            url: url,
            apiKey: apiKey,
            model: model,
            systemPrompt: Self.magicStreamingSystemPrompt,
            userMessage: Self.magicUserMessage(selectedText: selectedText, command: command),
            history: history,
            temperature: temperature,
            timeout: baseTimeout
        )
    }

    /// System prompt del modo streaming: pide header de control + texto plano.
    private static let magicStreamingSystemPrompt = """
    You are the "Magic Selection" assistant. The user selected some text and dictated (or typed) an instruction.

    Your reply MUST start with ONE control tag on the first line (literal, no quotes, no markdown, without the words "control tag"), and the content below it. Do NOT repeat these instructions or write "PART 1/2".

    Possible tags:
    - @@REPLACE@@ → the instruction transforms the text (translate, rephrase, rewrite, fix, summarize to replace). The result replaces the original.
    - @@ANSWER@@ → it is a question or asks for info (what it means, explain, give me synonyms, build a list). Shown without touching the text.
    - @@ANSWER|img=Entity@@ → like ANSWER, when an image illustrates it (place/person/animal/object/monument). E.g. @@ANSWER|img=Eiffel Tower@@.
    - @@ACTION|tool=notes@@ → save/add to Notes. Below, the content.
    - @@ACTION|tool=reminders@@ → create a reminder. Below, the text.
    - @@ACTION|tool=mail|subject=Subject@@ → write an email. Below, the body.
    - @@ACTION|tool=calendar|title=Title|date=YYYY-MM-DDTHH:mm@@ → create an event. If there is a date/time in the text, put it in date (ISO); otherwise, omit date.
    - @@ACTION|tool=maps|query=Place@@ → view an address/place on the map.
    - @@ACTION|tool=message@@ → send a message. Below, the already-drafted text.
    - @@ACTION|tool=call|number=+1…@@ → call a phone number (infer it from the text).
    - @@ACTION|tool=shortcut|name=Name@@ → run an Apple Shortcut. Below, its input.

    Content rules (what goes below the tag):
    - REPLACE: ONLY the transformed text, no preamble. Keep the language unless asked to translate.
    - ANSWER: reply in the language of the user's text/instruction, expert and useful, balanced (no filler). For code, show it in a markdown ``` block with the language.
    - ACTION: the content must be ready to be saved/sent. Use ACTION only if the instruction clearly asks to send something to that app.
    """

    nonisolated private static func magicUserMessage(selectedText: String, command: String) -> String {
        """
        <SELECTED_TEXT>
        \(selectedText)
        </SELECTED_TEXT>

        <INSTRUCTION>
        \(command)
        </INSTRUCTION>
        """
    }

    /// Parsea la línea de control en un `MagicControl`. Tolerante: ante
    /// cualquier cosa rara, asume answer (no toca el texto).
    nonisolated private static func parseControlHeader(_ header: String) -> MagicControl {
        let h = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = h.uppercased()

        if upper.hasPrefix("@@REPLACE") { return .replace }

        if upper.hasPrefix("@@ACTION") {
            let params = parseParams(h)
            let tool = params["tool"]?.lowercased() ?? ""
            if MagicActions.supportedTools.contains(tool) {
                return .action(tool: tool, params: params)
            }
            return .answer(imageQuery: nil)
        }

        if upper.hasPrefix("@@ANSWER") {
            let params = parseParams(h)
            let img = params["img"].flatMap { $0.isEmpty ? nil : $0 }
            return .answer(imageQuery: img)
        }

        return .answer(imageQuery: nil)
    }

    /// Extrae `clave=valor` separados por `|` de una etiqueta `@@TIPO|k=v|k2=v2@@`.
    nonisolated private static func parseParams(_ header: String) -> [String: String] {
        let inner = header.replacingOccurrences(of: "@@", with: "")
        var result: [String: String] = [:]
        for part in inner.split(separator: "|") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = kv[1].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    /// Para el fallback no-streaming: separa el header (1ª línea) del cuerpo.
    nonisolated static func parseHeaderResponse(_ raw: String) -> (MagicControl, String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Caso ideal: header en la 1ª línea, cuerpo debajo.
        if let nl = trimmed.firstIndex(of: "\n") {
            let header = String(trimmed[..<nl])
            if header.contains("@@") {
                let body = String(trimmed[trimmed.index(after: nl)...])
                return (parseControlHeader(header), cleanMagicArtifacts(body))
            }
        }
        // Header sin cuerpo (acción tipo maps/call que no lleva texto debajo).
        if trimmed.hasPrefix("@@"), !trimmed.contains("\n") {
            return (parseControlHeader(trimmed), "")
        }
        // Robusto: algunos modelos (ej. Apple on-device) envuelven la etiqueta
        // en markdown ("### PARTE 1 / @@ANSWER@@ / ### PARTE 2 …"). Buscamos la
        // etiqueta @@…@@ en cualquier parte, tomamos el texto que sigue y
        // limpiamos los artefactos del prompt.
        if let r = trimmed.range(of: "@@[A-Za-z][^@]*@@", options: .regularExpression) {
            let control = parseControlHeader(String(trimmed[r]))
            let after = String(trimmed[r.upperBound...])
            let body = cleanMagicArtifacts(after.isEmpty ? String(trimmed[..<r.lowerBound]) : after)
            return (control, body)
        }
        return (.answer(imageQuery: nil), cleanMagicArtifacts(trimmed))
    }

    /// Saca basura que algunos modelos chicos copian del prompt (encabezados
    /// "PARTE 1/2", "Etiqueta de control", etiquetas @@…@@ sueltas).
    nonisolated static func cleanMagicArtifacts(_ s: String) -> String {
        let cleaned = s.components(separatedBy: "\n").filter { line in
            let l = line.trimmingCharacters(in: .whitespaces).lowercased()
            if l.contains("parte 1") || l.contains("parte 2") { return false }
            if l.contains("etiqueta de control") || l.contains("etiqueta de control:") { return false }
            // Línea que es SOLO una etiqueta de control suelta.
            if l.hasPrefix("@@") && l.hasSuffix("@@") { return false }
            return true
        }.joined(separator: "\n")
        // Quitar etiquetas @@…@@ que hayan quedado inline.
        let stripped = cleaned.replacingOccurrences(of: "@@[A-Za-z][^@]*@@", with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mapLLMKitError(_ error: LLMKitError) -> EnhancementError {
        switch error {
        case .missingAPIKey:
            return .notConfigured
        case .httpError(let statusCode, let message):
            if statusCode == 429 { return .rateLimitExceeded }
            if (500...599).contains(statusCode) { return .serverError }
            return .customError("HTTP \(statusCode): \(message)")
        case .noResultReturned:
            return .enhancementFailed
        case .networkError:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidURL, .decodingError, .encodingError:
            return .customError(error.localizedDescription)
        }
    }

    private var retryOnTimeout: Bool {
        UserDefaults.standard.bool(forKey: "EnhancementRetryOnTimeout")
    }

    private func makeRequestWithRetry(text: String, mode: EnhancementPrompt, maxRetries: Int = 3, initialDelay: TimeInterval = 1.0) async throws -> String {
        var retries = 0
        var currentDelay = initialDelay

        while retries < maxRetries {
            do {
                return try await makeRequest(text: text, mode: mode)
            } catch let error as EnhancementError {
                switch error {
                case .networkError, .serverError, .rateLimitExceeded:
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries.")
                        throw error
                    }
                case .timeout:
                    if retryOnTimeout {
                        retries += 1
                        if retries < maxRetries {
                            logger.warning("Request timed out, retrying immediately... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        } else {
                            logger.error("Request timed out after \(maxRetries, privacy: .public) retries.")
                            throw error
                        }
                    } else {
                        logger.error("Request timed out, failing immediately (retry disabled).")
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed with network error, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries with network error.")
                        throw EnhancementError.networkError
                    }
                } else {
                    throw error
                }
            }
        }

        throw EnhancementError.enhancementFailed
    }

    func enhance(_ text: String) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        let promptName = activePrompt?.title

        // Gating de provider BYOK Pro: free solo permite providers locales
        // (Ollama, localCLI). Cualquier provider cloud con API key del user
        // requiere Pro. Es el doble check defensivo — la UI debería filtrar
        // antes, pero blindamos acá por si alguien parchea la View.
        let currentProvider = aiService.selectedProvider
        if currentProvider.requiresBYOKLicense, !FeatureGate.isAvailable(.byokEnhancement) {
            throw EnhancementError.proBYOKRequired
        }

        // Gating de prompts Pro: el user free solo puede usar el System
        // Default. Si seleccionó cualquier otro predefinido o un custom,
        // abortamos antes de gastar tokens. La UI del selector debería
        // bloquear esto upstream pero acá hay doble check de seguridad.
        if let active = activePrompt, !FeatureGate.isPromptAvailable(active.id) {
            throw EnhancementError.proPromptRequired
        }

        do {
            let result = try await makeRequestWithRetry(text: text, mode: enhancementPrompt)
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            // Tracking de gasto estimado: solo si el provider es de pago.
            // Para localCLI/ollama no tiene sentido porque corre con la
            // suscripción/cuenta del usuario.
            recordTokenUsageIfBillable(inputText: text, outputText: result)
            return (result, duration, promptName)
        } catch {
            throw error
        }
    }

    /// Estima tokens (heurística chars/3.5) y guarda un `TokenUsageRecord`
    /// si el provider activo es facturable. Errores silenciosos: tracking
    /// nunca debe romper la transcripción. La persistencia va por
    /// `TokenUsageStore` (UserDefaults JSON) para evitar crashes de
    /// migración SwiftData.
    private func recordTokenUsageIfBillable(inputText: String, outputText: String) {
        let inputTokens = TokenPricing.estimateTokens(from: inputText)
        let outputTokens = TokenPricing.estimateTokens(from: outputText)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let provider = self.aiService.selectedProvider.rawValue
            guard TokenPricing.isBillable(provider: provider) else { return }
            let model = self.aiService.currentModel
            let cost = TokenPricing.estimateCost(
                provider: provider,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
            let record = TokenUsageRecord(
                provider: provider,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                costUSD: cost
            )
            TokenUsageStore.shared.append(record)
        }
    }

    func captureScreenContext() async {
        guard CGPreflightScreenCaptureAccess() else {
            return
        }

        if await screenCaptureService.captureAndExtractText() != nil {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }

    func captureClipboardContext() {
        lastCapturedClipboard = NSPasteboard.general.string(forType: .string)
    }
    
    func clearCapturedContexts() {
        lastCapturedClipboard = nil
        screenCaptureService.lastCapturedText = nil
    }

    func addPrompt(title: String, promptText: String, icon: PromptIcon = "doc.text.fill", description: String? = nil, triggerWords: [String] = [], useSystemInstructions: Bool = true) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false, triggerWords: triggerWords, useSystemInstructions: useSystemInstructions)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }

    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }

    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }

    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }

    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()
        let validPredefinedIds = Set(predefinedTemplates.map { $0.id })

        // Limpieza de prompts predefinidos viejos que ya no están en el set
        // actual (ej: "Assistant" que se removió). Solo afecta prompts
        // marcados `isPredefined`; los custom del usuario no se tocan.
        customPrompts.removeAll { prompt in
            prompt.isPredefined && !validPredefinedIds.contains(prompt.id)
        }

        for template in predefinedTemplates {
            if let existingIndex = customPrompts.firstIndex(where: { $0.id == template.id }) {
                var updatedPrompt = customPrompts[existingIndex]
                updatedPrompt = CustomPrompt(
                    id: updatedPrompt.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: updatedPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: updatedPrompt.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
                customPrompts[existingIndex] = updatedPrompt
            } else {
                customPrompts.append(template)
            }
        }

        // Si el prompt seleccionado era el Assistant viejo (ya removido),
        // re-seleccionar el primero disponible.
        if let selected = selectedPromptId,
           !customPrompts.contains(where: { $0.id == selected }) {
            selectedPromptId = customPrompts.first?.id
        }
    }
}

enum EnhancementError: Error {
    case notConfigured
    case invalidResponse
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)
    /// Lanzado cuando el user free intenta usar uno de los 7 prompts
    /// extras (Chat, Email, Rewrite, Formal, Coding, Summary, Fun) o un
    /// custom prompt creado por él. El "System Default" sigue libre.
    case proPromptRequired
    /// Lanzado cuando el user free intenta usar Mejora con IA con un
    /// provider que requiere conexión a internet (Anthropic, OpenAI, Gemini,
    /// Groq, etc.). El escape válido en Free es Ollama local.
    case proBYOKRequired
}

extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .customError(let message):
            return message
        case .proPromptRequired:
            return "This prompt requires a Pro license. The free tier includes the System Default prompt — upgrade to Pro to unlock Chat, Email, Rewrite, Formal, Coding, Summary, Fun and custom prompts."
        case .proBYOKRequired:
            return "AI Enhancement with cloud providers (Anthropic, OpenAI, Gemini, Groq, etc.) requires a Pro license. The free tier includes Ollama local — install Ollama and pull a model to use AI Enhancement for free without any API key."
        }
    }
}
