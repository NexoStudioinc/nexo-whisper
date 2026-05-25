import Foundation
import OSLog

private let cliLogger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LocalCLIService")

enum LocalCLITemplate: String, CaseIterable, Identifiable {
    case pi
    case claude
    case codex
    case gemini
    case copilot
    case antigravity

    // Nota: .gemini removido del default a partir de junio 2026.
    // Google deprecó gemini-cli a favor de Antigravity (agy). Sigue
    // disponible como case por compatibilidad con usuarios que aún lo usen,
    // pero no aparece en el picker ni en el auto-detect.
    static var allCases: [LocalCLITemplate] {
        [.pi, .claude, .codex, .antigravity, .copilot]
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pi: return "Pi"
        case .claude: return "Claude / Anthropic"
        case .codex: return "Codex / OpenAI"
        case .gemini: return "Gemini CLI (deprecated)"
        case .copilot: return "Copilot"
        case .antigravity: return "Antigravity / Google"
        }
    }

    var defaultModel: String {
        switch self {
        case .codex:
            return "gpt-5.4-mini"
        case .claude:
            // haiku por default en lugar de sonnet: la transcripción mejorada
            // es una tarea simple de polish, no requiere razonamiento profundo.
            // Haiku responde en ~1-2s vs ~3-5s de sonnet → mejora notable de
            // latencia percibida. El usuario puede cambiar a sonnet/opus en
            // el picker si quiere más calidad a costo de tiempo.
            return "haiku"
        case .gemini:
            return "gemini-2.5-flash"
        case .pi, .copilot, .antigravity:
            // Antigravity y otros CLIs sin selector de modelo: el modelo se
            // configura via la cuenta del usuario en el CLI, no por argumento.
            return ""
        }
    }

    var availableModels: [String] {
        switch self {
        case .codex:
            return [
                "gpt-5.4-mini",
                "gpt-5.4",
                "gpt-5.5"
            ]
        case .claude:
            return [
                "sonnet",
                "haiku",
                "opus",
                "claude-sonnet-4-6",
                "claude-haiku-4-5",
                "claude-opus-4-6"
            ]
        case .gemini:
            return [
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.5-pro",
                "gemini-3-flash-preview",
                "gemini-3.1-flash-lite",
                "gemini-3.1-pro-preview"
            ]
        case .pi, .copilot, .antigravity:
            return []
        }
    }

    var commandTemplate: String {
        // Patrón claude/agy/gemini: leer prompt desde stdin (que Nexo escribe
        // automáticamente). Evita problemas de shell escaping con prompts
        // largos / multilínea / comillas / caracteres especiales que rompían
        // los call sites con "$VOICEINK_FULL_PROMPT" como argumento.
        switch self {
        case .pi:
            return "pi -ne -ns -p --no-tools --system-prompt \"$VOICEINK_SYSTEM_PROMPT\" \"$VOICEINK_USER_PROMPT\""
        case .claude:
            // claude lee de stdin con -p (sin argumento). El modelo se pasa con --model.
            // unset ANTHROPIC_API_KEY: si el usuario tiene una API key vieja exportada
            // en .zprofile/.zshenv, claude prioriza esa sobre OAuth Claude Code y falla
            // con "401 Invalid authentication credentials". Removiéndola, claude usa el
            // OAuth de Claude Code (subscription Pro/Max) que es lo que esperamos.
            // Si el usuario quiere usar API key, debería conectarse via "Anthropic"
            // como provider directo (no Local CLI).
            // Fallback de modelo: si VOICEINK_LOCAL_CLI_MODEL está vacío, sonnet por default.
            return "unset ANTHROPIC_API_KEY; claude -p --model \"${VOICEINK_LOCAL_CLI_MODEL:-sonnet}\""
        case .codex:
            // codex no soporta stdin: usamos archivo temporal.
            return "TMPFILE=$(mktemp) && codex exec --skip-git-repo-check --model \"$VOICEINK_LOCAL_CLI_MODEL\" --output-last-message \"$TMPFILE\" \"$VOICEINK_FULL_PROMPT\" > /dev/null 2>&1 && cat \"$TMPFILE\" && rm \"$TMPFILE\""
        case .gemini:
            return "gemini --skip-trust --model \"$VOICEINK_LOCAL_CLI_MODEL\" --prompt \"$VOICEINK_FULL_PROMPT\" --output-format text"
        case .copilot:
            return "copilot -p \"$VOICEINK_FULL_PROMPT\" -s --no-ask-user --available-tools=__none__ 2>/dev/null"
        case .antigravity:
            // Antigravity (agy) — reemplazo de gemini-cli a partir de junio 2026.
            // --print sin argumento lee de stdin (que Nexo escribe automáticamente
            // con el VOICEINK_FULL_PROMPT). Eso evita problemas de escaping bash
            // con prompts largos/multilínea que rompían cuando se pasaba como argv.
            // --dangerously-skip-permissions evita prompts de tools (no usamos).
            return "agy --print --dangerously-skip-permissions"
        }
    }

    /// Nombre del binario a buscar en el PATH del usuario para detección automática.
    var binaryName: String {
        switch self {
        case .pi: return "pi"
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .copilot: return "copilot"
        case .antigravity: return "agy"
        }
    }

    /// URL con instrucciones de instalación oficiales del CLI.
    var installHelpURL: URL? {
        switch self {
        case .claude: return URL(string: "https://docs.anthropic.com/en/docs/claude-code/quickstart")
        case .codex: return URL(string: "https://github.com/openai/codex-cli")
        case .gemini: return URL(string: "https://github.com/google-gemini/gemini-cli")
        case .copilot: return URL(string: "https://docs.github.com/en/copilot/github-copilot-in-the-cli")
        case .pi: return URL(string: "https://pi.ai")
        case .antigravity: return nil
        }
    }
}

final class LocalCLIService {
    static let commandTemplateKey = "localCLICommandTemplate"
    static let selectedTemplateKey = "localCLISelectedTemplate"
    static let selectedModelKey = "localCLISelectedModel"
    static let timeoutSecondsKey = "localCLITimeoutSeconds"
    static let defaultTimeoutSeconds: Double = 45
    private static let shellPathQueue = DispatchQueue(label: "com.prakashjoshipax.voiceink.localcli.path")
    private static var cachedInteractiveLoginPATH: String?

    var commandTemplate: String {
        didSet {
            UserDefaults.standard.set(commandTemplate, forKey: Self.commandTemplateKey)
        }
    }

    var selectedTemplate: LocalCLITemplate {
        didSet {
            UserDefaults.standard.set(selectedTemplate.rawValue, forKey: Self.selectedTemplateKey)
        }
    }

    var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: Self.selectedModelKey)
        }
    }

    var timeoutSeconds: Double {
        didSet {
            let clamped = max(5, timeoutSeconds)
            if clamped != timeoutSeconds {
                timeoutSeconds = clamped
                return
            }
            UserDefaults.standard.set(timeoutSeconds, forKey: Self.timeoutSecondsKey)
        }
    }

    var isConfigured: Bool {
        !commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let savedTemplateRaw = UserDefaults.standard.string(forKey: Self.selectedTemplateKey) ?? ""
        let savedTemplate = LocalCLITemplate(rawValue: savedTemplateRaw) ?? .pi
        let didFallbackFromUnsupportedTemplate = savedTemplate != Self.validTemplateOrFallback(savedTemplate)
        selectedTemplate = Self.validTemplateOrFallback(savedTemplate)
        let savedModel = UserDefaults.standard.string(forKey: Self.selectedModelKey) ?? ""
        if !savedModel.isEmpty && selectedTemplate.availableModels.contains(savedModel) {
            selectedModel = savedModel
        } else {
            selectedModel = selectedTemplate.defaultModel
        }

        commandTemplate = UserDefaults.standard.string(forKey: Self.commandTemplateKey) ?? ""

        if didFallbackFromUnsupportedTemplate || commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedModel = selectedTemplate.defaultModel
            commandTemplate = selectedTemplate.commandTemplate
        }

        let savedTimeout = UserDefaults.standard.double(forKey: Self.timeoutSecondsKey)
        timeoutSeconds = savedTimeout > 0 ? savedTimeout : Self.defaultTimeoutSeconds
    }

    func loadTemplate(_ template: LocalCLITemplate) {
        selectedTemplate = template
        selectedModel = template.defaultModel
        commandTemplate = template.commandTemplate
    }

    func updateSelectedModel(_ model: String) {
        selectedModel = model
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        // Gating: Mejora via CLI local (Claude Code / Codex / Antigravity /
        // Copilot / Pi) es feature Pro. Free puede usar Mejora via BYOK
        // (API key del user en AIService), pero no via CLI auto-detectada
        // del sistema. Razonamiento: BYOK ya es el camino "no te cobro 2
        // veces"; la CLI local es una conveniencia extra que justifica Pro.
        guard FeatureGate.isAvailable(.cliEnhancement) else {
            throw LocalCLIError.proLicenseRequired
        }

        guard isConfigured else {
            throw LocalCLIError.commandNotConfigured
        }

        let fullPrompt = Self.makeFullPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return try await executeCommand(
            commandTemplate: commandTemplate,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            fullPrompt: fullPrompt,
            timeout: timeoutSeconds
        )
    }

    static func makeFullPrompt(systemPrompt: String, userPrompt: String) -> String {
        """
        <SYSTEM_PROMPT>
        \(systemPrompt)
        </SYSTEM_PROMPT>

        <USER_PROMPT>
        \(userPrompt)
        </USER_PROMPT>
        """
    }

    private func executeCommand(
        commandTemplate: String,
        systemPrompt: String,
        userPrompt: String,
        fullPrompt: String,
        timeout: Double
    ) async throws -> String {
        let localCLIModel = selectedModel

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", commandTemplate]

                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = Self.preferredPATH(fallback: environment["PATH"])
                environment["VOICEINK_SYSTEM_PROMPT"] = systemPrompt
                environment["VOICEINK_USER_PROMPT"] = userPrompt
                environment["VOICEINK_FULL_PROMPT"] = fullPrompt
                environment["VOICEINK_LOCAL_CLI_MODEL"] = localCLIModel
                process.environment = environment

                let inputPipe = Pipe()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LocalCLIError.executionFailed(error.localizedDescription))
                    return
                }

                if let inputData = fullPrompt.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                }
                try? inputPipe.fileHandleForWriting.close()

                // Lectura asíncrona de los pipes mientras el proceso corre.
                //
                // Antes leíamos con readDataToEndOfFile() DESPUÉS de esperar
                // el semáforo de terminación. Eso provoca deadlock si el CLI
                // produce salida > ~64KB (tamaño del buffer del pipe en macOS):
                // el subproceso queda bloqueado en write(), y nuestro hilo
                // bloqueado en semaphore.wait() — los dos esperándose. La app
                // solo se destrababa al hit de timeout, perdiendo la mejora.
                //
                // Ahora drenamos stdout y stderr en background mientras el
                // proceso corre, así el buffer del pipe nunca se llena.
                let readGroup = DispatchGroup()
                var stdoutData = Data()
                var stderrData = Data()
                let outputLock = NSLock()

                readGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    outputLock.lock()
                    stdoutData = data
                    outputLock.unlock()
                    readGroup.leave()
                }

                readGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    outputLock.lock()
                    stderrData = data
                    outputLock.unlock()
                    readGroup.leave()
                }

                let semaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    semaphore.signal()
                }

                let waitResult = semaphore.wait(timeout: .now() + timeout)
                if waitResult == .timedOut {
                    if process.isRunning {
                        process.terminate()
                        _ = semaphore.wait(timeout: .now() + 2)
                    }
                    // Esperamos a que los lectores en background terminen
                    // (cierran al recibir EOF cuando el proceso es terminado)
                    // para no dejar hilos colgados.
                    _ = readGroup.wait(timeout: .now() + 2)
                    continuation.resume(throwing: LocalCLIError.timeout(seconds: timeout))
                    return
                }

                // Drenar el resto de los buffers después de que el proceso terminó.
                readGroup.wait()

                let stdout = Self.cleanOutput(String(data: stdoutData, encoding: .utf8) ?? "")
                let stderr = Self.cleanOutput(String(data: stderrData, encoding: .utf8) ?? "")

                if process.terminationStatus != 0 {
                    // Logging detallado para diagnosticar fallos de CLI.
                    // Visible en Console.app filtrando por "LocalCLIService".
                    cliLogger.error("CLI exit=\(process.terminationStatus, privacy: .public) cmd=\(commandTemplate, privacy: .public)")
                    cliLogger.error("CLI stderr (first 500 chars): \(String(stderr.prefix(500)), privacy: .public)")
                    cliLogger.error("CLI stdout (first 500 chars): \(String(stdout.prefix(500)), privacy: .public)")

                    let looksLikeCommandNotFound = process.terminationStatus == 127 ||
                        stderr.lowercased().contains("command not found")
                    if looksLikeCommandNotFound {
                        continuation.resume(throwing: LocalCLIError.commandNotFound(stderr.isEmpty ? commandTemplate : stderr))
                    } else {
                        continuation.resume(throwing: LocalCLIError.nonZeroExit(status: Int(process.terminationStatus), stderr: stderr))
                    }
                    return
                }

                guard !stdout.isEmpty else {
                    cliLogger.error("CLI returned empty stdout. cmd=\(commandTemplate, privacy: .public) stderr=\(String(stderr.prefix(500)), privacy: .public)")
                    continuation.resume(throwing: LocalCLIError.emptyOutput)
                    return
                }

                continuation.resume(returning: stdout)
            }
        }
    }

    private static func validTemplateOrFallback(_ template: LocalCLITemplate) -> LocalCLITemplate {
        LocalCLITemplate.allCases.contains(template) ? template : .pi
    }

    private static func preferredPATH(fallback: String?) -> String {
        shellPathQueue.sync {
            if let cachedInteractiveLoginPATH {
                return cachedInteractiveLoginPATH
            }

            if let discovered = discoverPATHFromInteractiveLoginShell() {
                cachedInteractiveLoginPATH = discovered
                return discovered
            }

            return fallback?.isEmpty == false ? fallback! : "/usr/bin:/bin:/usr/sbin:/sbin"
        }
    }

    private static func discoverPATHFromInteractiveLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -lc (login, NOT interactive) en lugar de -ilc para evitar que zsh
        // cargue .zshrc completo. .zshrc del usuario suele tocar directorios
        // protegidos (~/Pictures, ~/Music, ~/Documents via oh-my-zsh, plugins,
        // alias custom) lo que dispara dialogs de TCC pidiéndole a Nexo Whisper
        // permisos para esas carpetas. Solo necesitamos PATH, que se setea en
        // .zprofile/.zlogin (login shell) — no hace falta .zshrc.
        process.arguments = [
            "-lc",
            "echo __VOICEINK_PATH_START__; print -r -- $PATH; echo __VOICEINK_PATH_END__"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }
        let waitResult = semaphore.wait(timeout: .now() + 3)
        if waitResult == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let startMarker = "__VOICEINK_PATH_START__"
        let endMarker = "__VOICEINK_PATH_END__"

        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker, range: startRange.upperBound..<output.endIndex)
        else {
            return nil
        }

        let pathSection = output[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pathSection.isEmpty else {
            return nil
        }

        return pathSection
    }

    private static func cleanOutput(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cache de timestamps de pre-warm por binario, para debounce.
    /// Si el usuario clickea "Usar este" varias veces seguidas no queremos
    /// lanzar N procesos. 30s es suficiente: el binario sigue caliente en RAM.
    private static var lastPrewarmTimestamps: [String: Date] = [:]
    private static let prewarmLock = NSLock()
    private static let prewarmDebounceInterval: TimeInterval = 30

    /// Pre-warm: lanza el binario con --help (o similar) en background para
    /// que macOS cachee el binario en RAM. La primera invocación real evita
    /// pagar el cold start del proceso (~300-800ms en CLIs Node/Go).
    /// Costo: 1 proceso que vive ~1 segundo y muere. Despreciable.
    static func prewarm(binaryName: String) {
        prewarmLock.lock()
        if let last = lastPrewarmTimestamps[binaryName],
           Date().timeIntervalSince(last) < prewarmDebounceInterval {
            prewarmLock.unlock()
            cliLogger.notice("prewarm: \(binaryName, privacy: .public) skipped (debounced)")
            return
        }
        lastPrewarmTimestamps[binaryName] = Date()
        prewarmLock.unlock()

        DispatchQueue.global(qos: .utility).async {
            // Buscamos el binario sin shell (mismo approach que isBinaryAvailable)
            let home = NSHomeDirectory()
            let commonPaths = [
                "/opt/homebrew/bin", "/usr/local/bin",
                "\(home)/.local/bin", "\(home)/bin",
                "/usr/bin", "/bin", "/usr/sbin", "/sbin"
            ]
            var resolvedPath: String?
            for dir in commonPaths {
                let candidate = (dir as NSString).appendingPathComponent(binaryName)
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    resolvedPath = candidate
                    break
                }
            }
            guard let binaryPath = resolvedPath else {
                cliLogger.notice("prewarm: \(binaryName, privacy: .public) not found in common paths, skipping")
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["--help"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                // Esperamos máximo 3 segundos para que termine; si tarda más,
                // matamos el proceso (no nos importa el output, solo el cache).
                let waitDeadline = Date().addingTimeInterval(3)
                while process.isRunning && Date() < waitDeadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if process.isRunning {
                    process.terminate()
                }
                cliLogger.notice("prewarm: \(binaryName, privacy: .public) warmed")
            } catch {
                cliLogger.notice("prewarm: \(binaryName, privacy: .public) launch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Verifica si un binario está disponible para Nexo Whisper.
    /// Usado por CLIDetectionPanel para detectar automáticamente qué CLIs
    /// (claude/codex/agy/copilot) tiene instalados el usuario.
    ///
    /// Estrategia en 2 fases (cero riesgo de TCC dialogs):
    /// 1. Chequear paths comunes hardcoded — cubre Homebrew (Apple Silicon
    ///    e Intel), installs de usuario (~/.local/bin, ~/bin) y sistema.
    ///    Cero shell, cero acceso a directorios protegidos.
    /// 2. Si no se encontró, fallback al PATH del proceso (env var) y al
    ///    PATH descubierto via login shell (solo si está cacheado de un
    ///    uso anterior).
    ///
    /// NO usamos `-ilc` (interactive login shell) porque eso carga .zshrc
    /// y los plugins/aliases de zsh pueden tocar ~/Pictures, ~/Music, etc.,
    /// disparando dialogs TCC que confunden al usuario.
    static func isBinaryAvailable(named binaryName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let home = NSHomeDirectory()
                let commonPaths: [String] = [
                    "/opt/homebrew/bin",                 // Homebrew Apple Silicon
                    "/usr/local/bin",                    // Homebrew Intel + manual installs
                    "\(home)/.local/bin",                // Installs de usuario (pipx, agy, etc)
                    "\(home)/bin",                       // ~/bin clásico
                    "/usr/bin",
                    "/bin",
                    "/usr/sbin",
                    "/sbin"
                ]
                for dir in commonPaths {
                    let candidate = (dir as NSString).appendingPathComponent(binaryName)
                    if FileManager.default.isExecutableFile(atPath: candidate) {
                        continuation.resume(returning: true)
                        return
                    }
                }

                // Fallback: PATH del proceso (puede no tener custom paths del user)
                if let envPath = ProcessInfo.processInfo.environment["PATH"] {
                    for dir in envPath.split(separator: ":").map(String.init) {
                        let candidate = (dir as NSString).appendingPathComponent(binaryName)
                        if FileManager.default.isExecutableFile(atPath: candidate) {
                            continuation.resume(returning: true)
                            return
                        }
                    }
                }

                continuation.resume(returning: false)
            }
        }
    }
}

enum LocalCLIError: Error, LocalizedError {
    case commandNotConfigured
    case commandNotFound(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int, stderr: String)
    case emptyOutput
    case executionFailed(String)
    /// Lanzado cuando se intenta usar CLI enhancement sin licencia Pro.
    /// El user free puede usar Mejora via BYOK (API key), pero la
    /// auto-detección de CLIs del sistema requiere upgrade.
    case proLicenseRequired

    var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return "Local CLI command is not configured. Load a template or enter a command first."
        case .commandNotFound(let details):
            return "Local CLI command was not found. Use an absolute path or fix your shell PATH. Details: \(details)"
        case .timeout(let seconds):
            return "Local CLI command timed out after \(Int(seconds)) seconds."
        case .nonZeroExit(let status, let stderr):
            if stderr.isEmpty {
                return "Local CLI command failed with exit code \(status)."
            }
            return "Local CLI command failed with exit code \(status): \(stderr)"
        case .emptyOutput:
            return "Local CLI command returned empty output."
        case .executionFailed(let message):
            return "Failed to execute Local CLI command: \(message)"
        case .proLicenseRequired:
            return "Local CLI enhancement requires a Pro license. You can still use AI Enhancement with your own API key (BYOK) in the free tier."
        }
    }
}
