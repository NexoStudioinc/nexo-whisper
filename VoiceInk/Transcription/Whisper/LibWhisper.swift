import Foundation
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os


// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext {
    private var context: OpaquePointer?
    private var prompt: String?
    private var vadModelPath: String?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperContext")

    private init() {}

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    func fullTranscribe(samples: [Float]) -> Bool {
        guard let context = context else { return false }

        // Refactor 2026-05: antes asignábamos `params.language` y
        // `params.initial_prompt` con punteros obtenidos vía
        // `withUnsafeBufferPointer` cuyo lifetime expira al cerrar el closure.
        // Aunque funcionaba "por suerte" (los arrays eran stored properties
        // del actor), técnicamente era undefined behavior por escape de puntero.
        // Ahora anidamos `withCString` para que `whisper_full` se invoque
        // DENTRO del lifetime de los punteros C — garantía de validez.
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        let languageToUse: String? = selectedLanguage == "auto" ? nil : selectedLanguage
        let promptToUse: String? = self.prompt

        return Self.withOptionalCString(languageToUse) { langPtr in
            return Self.withOptionalCString(promptToUse) { promptPtr in
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.language = langPtr
                params.initial_prompt = promptPtr

                params.print_realtime = true
                params.print_progress = false
                params.print_timestamps = true
                params.print_special = false
                params.translate = false
                let maxThreads = max(1, min(8, cpuCount() - 2))
                params.n_threads = Int32(maxThreads)
                params.offset_ms = 0
                params.no_context = true
                params.single_segment = false
                params.temperature = 0.2

                whisper_reset_timings(context)

                // Configure VAD if enabled by user and model is available
                let isVADEnabled = UserDefaults.standard.bool(forKey: "IsVADEnabled")
                if isVADEnabled, let vadModelPath = self.vadModelPath {
                    params.vad = true
                    params.vad_model_path = (vadModelPath as NSString).utf8String

                    var vadParams = whisper_vad_default_params()
                    vadParams.threshold = 0.50
                    vadParams.min_speech_duration_ms = 250
                    vadParams.min_silence_duration_ms = 100
                    vadParams.max_speech_duration_s = Float.greatestFiniteMagnitude
                    vadParams.speech_pad_ms = 30
                    vadParams.samples_overlap = 0.1
                    params.vad_params = vadParams
                } else {
                    params.vad = false
                }

                var success = true
                samples.withUnsafeBufferPointer { samplesBuffer in
                    if whisper_full(context, params, samplesBuffer.baseAddress, Int32(samplesBuffer.count)) != 0 {
                        logger.error("❌ Failed to run whisper_full. VAD enabled: \(params.vad, privacy: .public)")
                        success = false
                    }
                }
                return success
            }
        }
    }

    /// Helper para invocar `body` con un `UnsafePointer<CChar>?` válido
    /// durante toda la ejecución del closure. Si `string` es nil, pasa nil.
    /// Garantiza que el puntero NO escape — se invalida al retornar.
    private static func withOptionalCString<Result>(
        _ string: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        if let string = string {
            return string.withCString { ptr in
                body(ptr)
            }
        } else {
            return body(nil)
        }
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
    }

    static func createContext(path: String) async throws -> WhisperContext {
        let whisperContext = WhisperContext()
        try await whisperContext.initializeModel(path: path)
        
        // Load VAD model from bundle resources
        let vadModelPath = await VADModelManager.shared.getModelPath()
        await whisperContext.setVADModelPath(vadModelPath)
        
        return whisperContext
    }
    
    private func initializeModel(path: String) throws {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        logger.info("Running on the simulator, using CPU")
        #else
        params.flash_attn = true // Enable flash attention for Metal
        logger.info("Flash attention enabled for Metal")
        #endif
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            logger.error("❌ Couldn't load model at \(path, privacy: .public)")
            throw VoiceInkEngineError.modelLoadFailed
        }
    }
    
    private func setVADModelPath(_ path: String?) {
        self.vadModelPath = path
        if path != nil {
            logger.info("VAD model loaded from bundle resources")
        }
    }

    func releaseResources() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
        // Ya no hay stored properties de CString — los punteros C se manejan
        // 100% dentro de los closures `withCString` por scope.
    }

    func setPrompt(_ prompt: String?) {
        self.prompt = prompt
    }
}

fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
