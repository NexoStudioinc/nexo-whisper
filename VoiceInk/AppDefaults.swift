import Foundation

enum AppDefaults {
    /// Auto-detect del idioma del sistema para usarlo como default de Whisper.
    /// Si el Mac está en español → Whisper transcribe español por default.
    /// Esto evita que un user hispanohablante reciba transcripciones rotas
    /// por tener Whisper forzado a inglés (causa raíz del bug "la mejora
    /// me sale en inglés").
    ///
    /// El user puede cambiarlo manualmente después en Settings — el picker
    /// del modelo soporta 99 idiomas y "auto" (Whisper detecta).
    ///
    /// Side feature: si el user dicta en su idioma pero selecciona OTRO
    /// idioma acá, Whisper transcribe en el seleccionado (modo traducción
    /// implícita — limitado, solo funciona bien con destino inglés).
    private static var defaultWhisperLanguage: String {
        let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
        // Lista de idiomas core soportados por Whisper que también soportamos
        // bien en la app. Si el sistema usa algo fuera de esto, fallback a "en".
        let supportedDefaults: Set<String> = [
            "en", "es", "pt", "fr", "de", "it",
            "ja", "ko", "zh", "ru", "ar"
        ]
        return supportedDefaults.contains(systemLang) ? systemLang : "en"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // Onboarding & General
            "hasCompletedOnboarding": false,
            "enableAnnouncements": true,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,

            // Audio & Media
            "isSystemMuteEnabled": true,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": false,
            "isSoundFeedbackEnabled": true,
            CustomSoundManager.SoundType.start.builtInSoundKey: CustomSoundManager.SoundType.start.defaultBuiltInSound.rawValue,
            CustomSoundManager.SoundType.stop.builtInSoundKey: CustomSoundManager.SoundType.stop.defaultBuiltInSound.rawValue,

            // Recording & Transcription
            "IsTextFormattingEnabled": true,
            "IsVADEnabled": true,
            "RemoveFillerWords": true,
            "RemovePunctuation": false,
            "LowercaseTranscription": false,
            "SelectedLanguage": defaultWhisperLanguage,
            "AppendTrailingSpace": true,
            "showLiveTextPreview": false,
            "RecorderType": "mini",

            // Cleanup
            "IsTranscriptionCleanupEnabled": false,
            "TranscriptionRetentionMinutes": 1440,
            "IsAudioCleanupEnabled": false,
            "AudioRetentionPeriod": 7,

            // UI & Behavior
            "IsMenuBarOnly": false,
            "powerModePersistConfig": false,
            // Shortcuts
            "isMiddleClickToggleEnabled": false,
            "middleClickActivationDelay": 200,

            // Enhancement
            "SkipShortEnhancement": true,
            "ShortEnhancementWordThreshold": 3,
            "EnhancementTimeoutSeconds": 7,
            "EnhancementRetryOnTimeout": true,

            // Model
            "PrewarmModelOnWake": true,

        ])

        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
        PasteMethod.migrateLegacyUserDefaultIfNeeded()
    }
}
