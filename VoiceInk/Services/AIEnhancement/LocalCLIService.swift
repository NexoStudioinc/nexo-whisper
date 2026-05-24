import Foundation

enum LocalCLITemplate: String, CaseIterable, Identifiable {
    case pi
    case claude
    case codex
    case gemini
    case copilot
    case antigravity

    static var allCases: [LocalCLITemplate] {
        [.pi, .claude, .codex, .gemini, .copilot]
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pi: return "Pi"
        case .claude: return "Claude / Anthropic"
        case .codex: return "Codex / OpenAI"
        case .gemini: return "Gemini / Google"
        case .copilot: return "Copilot"
        case .antigravity: return "Antigravity"
        }
    }

    var defaultModel: String {
        switch self {
        case .codex:
            return "gpt-5.4-mini"
        case .claude:
            return "sonnet"
        case .gemini:
            return "gemini-2.5-flash"
        case .pi, .copilot, .antigravity:
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
        switch self {
        case .pi:
            return "pi -ne -ns -p --no-tools --system-prompt \"$VOICEINK_SYSTEM_PROMPT\" \"$VOICEINK_USER_PROMPT\""
        case .claude:
            return "claude -p --model \"$VOICEINK_LOCAL_CLI_MODEL\" \"$VOICEINK_FULL_PROMPT\""
        case .codex:
            return "TMPFILE=$(mktemp) && codex exec --skip-git-repo-check --model \"$VOICEINK_LOCAL_CLI_MODEL\" --output-last-message \"$TMPFILE\" \"$VOICEINK_FULL_PROMPT\" > /dev/null 2>&1 && cat \"$TMPFILE\" && rm \"$TMPFILE\""
        case .gemini:
            return "gemini --skip-trust --model \"$VOICEINK_LOCAL_CLI_MODEL\" --prompt \"$VOICEINK_FULL_PROMPT\" --output-format text"
        case .copilot:
            return "copilot -p \"$VOICEINK_FULL_PROMPT\" -s --no-ask-user --available-tools=__none__ 2>/dev/null"
        case .antigravity:
            return "agy --print \"$VOICEINK_FULL_PROMPT\""
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
                    continuation.resume(throwing: LocalCLIError.timeout(seconds: timeout))
                    return
                }

                let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = Self.cleanOutput(String(data: stdoutData, encoding: .utf8) ?? "")
                let stderr = Self.cleanOutput(String(data: stderrData, encoding: .utf8) ?? "")

                if process.terminationStatus != 0 {
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
        process.arguments = [
            "-ilc",
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

    /// Verifica si un binario está disponible en el PATH del usuario.
    /// Usado por CLIDetectionPanel para detectar automáticamente qué CLIs
    /// (claude/codex/gemini/copilot) tiene instalados y ofrecer un setup
    /// con un clic.
    static func isBinaryAvailable(named binaryName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            shellPathQueue.async {
                let path = preferredPATH(fallback: ProcessInfo.processInfo.environment["PATH"])
                let dirs = path.split(separator: ":").map(String.init)
                for dir in dirs {
                    let candidate = (dir as NSString).appendingPathComponent(binaryName)
                    if FileManager.default.isExecutableFile(atPath: candidate) {
                        continuation.resume(returning: true)
                        return
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
        }
    }
}
