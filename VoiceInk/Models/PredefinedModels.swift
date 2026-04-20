import Foundation

enum PredefinedModels {

    static var models: [any TranscriptionModel] {
        return predefinedModels + CustomModelManager.shared.customModels
    }
    
    private static let predefinedModels: [any TranscriptionModel] = [
        // Native Apple Model
        NativeAppleModel(
            name: "apple-speech",
            displayName: "Apple Speech",
            description: "Uses the native Apple Speech framework for transcription. Requires macOS 26",
            isMultilingualModel: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .nativeApple)
        ),
        
        // Parakeet Models
        FluidAudioModel(
            name: "parakeet-tdt-0.6b-v2",
            displayName: "Parakeet V2",
            description: "NVIDIA's Parakeet V2 model optimized for lightning-fast English-only transcription",
            size: "474 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .fluidAudio)
        ),
        FluidAudioModel(
            name: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet V3",
            description: "NVIDIA's Parakeet V3 model with multilingual support across English and 25 European languages",
            size: "494 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .fluidAudio)
        ),

         // Local Models
         LocalModel(
             name: "ggml-tiny",
             displayName: "Tiny",
             size: "75 MB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .local),
             description: "Tiny model, fastest, least accurate",
             speed: 0.95,
             accuracy: 0.6,
             ramUsage: 0.3
         ),
         LocalModel(
             name: "ggml-tiny.en",
             displayName: "Tiny (English)",
             size: "75 MB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .local),
             description: "Tiny model optimized for English, fastest, least accurate",
             speed: 0.95,
             accuracy: 0.65,
             ramUsage: 0.3
         ),
         LocalModel(
             name: "ggml-base",
             displayName: "Base",
             size: "142 MB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .local),
             description: "Base model, good balance between speed and accuracy, supports multiple languages",
             speed: 0.85,
             accuracy: 0.72,
             ramUsage: 0.5
         ),
         LocalModel(
             name: "ggml-base.en",
             displayName: "Base (English)",
             size: "142 MB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .local),
             description: "Base model optimized for English, good balance between speed and accuracy",
             speed: 0.85,
             accuracy: 0.75,
             ramUsage: 0.5
         ),
         LocalModel(
             name: "ggml-large-v2",
             displayName: "Large v2",
             size: "2.9 GB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .local),
             description: "Large model v2, slower than Medium but more accurate",
             speed: 0.3,
             accuracy: 0.96,
             ramUsage: 3.8
         ),
         LocalModel(
             name: "ggml-large-v3",
             displayName: "Large v3",
             size: "2.9 GB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .local),
             description: "Large model v3, very slow but most accurate",
             speed: 0.3,
             accuracy: 0.98,
             ramUsage: 3.9
         ),
         LocalModel(
             name: "ggml-large-v3-turbo",
             displayName: "Large v3 Turbo",
             size: "1.5 GB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .local),
             description:
             "Large model v3 Turbo, faster than v3 with similar accuracy",
             speed: 0.75,
             accuracy: 0.97,
             ramUsage: 1.8
         ),
         LocalModel(
             name: "ggml-large-v3-turbo-q5_0",
             displayName: "Large v3 Turbo (Quantized)",
             size: "547 MB",
             supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .local),
             description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
             speed: 0.75,
             accuracy: 0.95,
             ramUsage: 1.0
         ),

                 // Cloud Models
        CloudModel(
            name: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo (Groq)",
            description: "Whisper Large v3 Turbo model with Groq's lightning-speed inference",
            provider: .groq,
            speed: 0.65,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .groq)
        ),
        CloudModel(
           name: "scribe_v1",
           displayName: "Scribe v1 (ElevenLabs)",
           description: "ElevenLabs' Scribe model for fast & accurate transcription",
           provider: .elevenLabs,
           speed: 0.7,
           accuracy: 0.98,
           isMultilingual: true,
           supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .elevenLabs)
       ),
       CloudModel(
           name: "scribe_v2",
           displayName: "Scribe V2 (ElevenLabs)",
           description: "ElevenLabs' Scribe V2 model for the most accurate transcription",
           provider: .elevenLabs,
           speed: 0.99,
           accuracy: 0.98,
           isMultilingual: true,
           supportsStreaming: true,
           supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .elevenLabs)
       ),
       CloudModel(
           name: "nova-3",
           displayName: "Nova 3 (Deepgram)",
           description: "Deepgram's latest Nova 3 model for fast, accurate transcription",
           provider: .deepgram,
           speed: 0.99,
           accuracy: 0.96,
           isMultilingual: true,
           supportsStreaming: true,
           supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .deepgram)
       ),
       CloudModel(
           name: "nova-3-medical",
           displayName: "Nova 3 Medical (Deepgram)",
           description: "Specialized medical transcription model optimized for clinical environments",
           provider: .deepgram,
           speed: 0.99,
           accuracy: 0.96,
           isMultilingual: false,
           supportsStreaming: true,
           supportedLanguages: LanguageDictionary.forProvider(isMultilingual: false, provider: .deepgram)
       ),
        CloudModel(
            name: "voxtral-mini-latest",
            displayName: "Voxtral (Mistral)",
            description: "Mistral's Voxtral model for fast and accurate transcription",
            provider: .mistral,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .mistral)
        ),
        CloudModel(
            name: "grok-stt",
            displayName: "Grok (xAI)",
            description: "xAI's Grok speech-to-text with real-time streaming and batch transcription",
            provider: .xai,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .xai)
        ),

        // Gemini Models
        CloudModel(
            name: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            description: "Google's advanced model with high-quality transcription capabilities",
            provider: .gemini,
            speed: 0.7,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            description: "Google's optimized model for low-latency transcription",
            provider: .gemini,
            speed: 0.9,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro",
            description: "Google's latest model with enhanced transcription capabilities",
            provider: .gemini,
            speed: 0.75,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-3-flash-preview",
            displayName: "Gemini 3 Flash",
            description: "Google's newest fast model combining intelligence with superior speed",
            provider: .gemini,
            speed: 0.92,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
        )
        ,
        CloudModel(
            name: "stt-async-v4",
            displayName: "Soniox V4",
            description: "Soniox transcription model v4 with human-parity accuracy",
            provider: .soniox,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .soniox)
        ),

        // Speechmatics Models
        CloudModel(
            name: "speechmatics-enhanced",
            displayName: "Speechmatics",
            description: "Speechmatics enhanced accuracy transcription with real-time streaming and 50+ language support",
            provider: .speechmatics,
            speed: 0.99,
            accuracy: 0.98,
            isMultilingual: true,
            supportsStreaming: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .speechmatics)
        )
     ]
 }
