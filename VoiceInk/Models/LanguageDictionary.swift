import Foundation

enum LanguageDictionary {

    static func forProvider(isMultilingual: Bool, provider: ModelProvider = .local) -> [String: String] {
        if !isMultilingual {
            return ["en": "English"]
        }

        switch provider {
        case .nativeApple:
            let codes = ["ar", "de", "en", "es", "fr", "it", "ja", "ko", "pt", "yue", "zh"]
            return all.filter { codes.contains($0.key) }

        case .fluidAudio:
            // Parakeet V3: 25 European languages (auto-detects internally)
            let codes = [
                "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
                "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro",
                "ru", "sk", "sl", "sv", "uk"
            ]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        case .groq:
            // Whisper Large v3 Turbo — same language set as local Whisper
            return all

        case .elevenLabs:
            // Scribe v1 & v2: 99 languages
            let codes = [
                "af", "am", "ar", "as", "az", "be", "bg", "bn", "bs", "ca",
                "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa",
                "fi", "fil", "fr", "ga", "gl", "gu", "ha", "he", "hi", "hr",
                "hu", "hy", "id", "ig", "is", "it", "ja", "jw", "ka", "kk",
                "km", "kn", "ko", "ku", "ky", "lb", "ln", "lo", "lt", "lv",
                "mi", "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl",
                "no", "or", "pa", "pl", "ps", "pt", "ro", "ru", "sd", "sk",
                "sl", "sn", "so", "sr", "sv", "sw", "ta", "tg", "te", "th",
                "tr", "uk", "ur", "uz", "vi", "wo", "xh", "yo", "yue", "zh", "zu"
            ]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        case .deepgram:
            // Nova-3: ~50 languages
            let codes = [
                "ar", "be", "bg", "bn", "bs", "ca", "cs", "da", "de", "el",
                "en", "es", "et", "fa", "fi", "fr", "he", "hi", "hr", "hu",
                "id", "it", "ja", "kn", "ko", "lt", "lv", "mk", "mr", "ms",
                "nl", "no", "pl", "pt", "ro", "ru", "sk", "sl", "sr", "sv",
                "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "zh"
            ]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        case .mistral:
            // Voxtral: 13 languages
            let codes = ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh"]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        case .gemini:
            // Gemini 2.5 Pro/Flash: 97+ languages — broad enough to use full list
            return all

        case .xai:
            // Grok STT: 25 languages
            let codes = [
                "ar", "cs", "da", "nl", "en", "fil", "fr", "de", "hi", "id",
                "it", "ja", "ko", "mk", "ms", "fa", "pl", "pt", "ro", "ru",
                "es", "sv", "th", "tr", "vi"
            ]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        case .soniox:
            // stt-async-v4: 60 languages (verified against OpenAPI schema)
            let codes = [
                "af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca",
                "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl",
                "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn",
                "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa",
                "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw",
                "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy"
            ]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        case .speechmatics:
            // Enhanced accuracy model: 50+ languages
            let codes = [
                "ar", "ba", "eu", "be", "bn", "bg", "yue", "ca", "hr", "cs", "da",
                "nl", "en", "et", "fi", "fr", "gl", "de", "el", "he", "hi",
                "hu", "id", "it", "ja", "ko", "lv", "lt", "ms", "mt", "mr",
                "mn", "no", "fa", "pl", "pt", "ro", "ru", "sk", "sl", "es",
                "sw", "sv", "tl", "ta", "th", "tr", "uk", "ur", "vi", "cy",
                "zh"
            ]
            var filtered = all.filter { codes.contains($0.key) }
            filtered["auto"] = "Auto-detect"
            return filtered

        case .local, .custom:
            // Local Whisper models support the full language list
            return all
        }
    }

    // Apple Native Speech languages in BCP-47 format
    // Based on actual supported locales from SpeechTranscriber.supportedLocales
    static let appleNative: [String: String] = [
        "en-US": "English (United States)",
        "en-GB": "English (United Kingdom)",
        "en-CA": "English (Canada)",
        "en-AU": "English (Australia)",
        "en-IN": "English (India)",
        "en-IE": "English (Ireland)",
        "en-NZ": "English (New Zealand)",
        "en-ZA": "English (South Africa)",
        "en-SA": "English (Saudi Arabia)",
        "en-AE": "English (UAE)",
        "en-SG": "English (Singapore)",
        "en-PH": "English (Philippines)",
        "en-ID": "English (Indonesia)",
        "es-ES": "Spanish (Spain)",
        "es-MX": "Spanish (Mexico)",
        "es-US": "Spanish (United States)",
        "es-CO": "Spanish (Colombia)",
        "es-CL": "Spanish (Chile)",
        "es-419": "Spanish (Latin America)",
        "fr-FR": "French (France)",
        "fr-CA": "French (Canada)",
        "fr-BE": "French (Belgium)",
        "fr-CH": "French (Switzerland)",
        "de-DE": "German (Germany)",
        "de-AT": "German (Austria)",
        "de-CH": "German (Switzerland)",
        "zh-CN": "Chinese Simplified (China)",
        "zh-TW": "Chinese Traditional (Taiwan)",
        "zh-HK": "Chinese Traditional (Hong Kong)",
        "ja-JP": "Japanese (Japan)",
        "ko-KR": "Korean (South Korea)",
        "yue-CN": "Cantonese (China)",
        "pt-BR": "Portuguese (Brazil)",
        "pt-PT": "Portuguese (Portugal)",
        "it-IT": "Italian (Italy)",
        "it-CH": "Italian (Switzerland)",
        "ar-SA": "Arabic (Saudi Arabia)"
    ]

    static let all: [String: String] = [
        "auto": "Auto-detect",
        "af": "Afrikaans",
        "am": "Amharic",
        "ar": "Arabic",
        "as": "Assamese",
        "az": "Azerbaijani",
        "ba": "Bashkir",
        "be": "Belarusian",
        "bg": "Bulgarian",
        "bn": "Bengali",
        "bo": "Tibetan",
        "br": "Breton",
        "bs": "Bosnian",
        "ca": "Catalan",
        "cs": "Czech",
        "cy": "Welsh",
        "da": "Danish",
        "de": "German",
        "el": "Greek",
        "en": "English",
        "es": "Spanish",
        "et": "Estonian",
        "eu": "Basque",
        "fa": "Persian",
        "fi": "Finnish",
        "fil": "Filipino",
        "fo": "Faroese",
        "fr": "French",
        "ga": "Irish",
        "gl": "Galician",
        "gu": "Gujarati",
        "ha": "Hausa",
        "haw": "Hawaiian",
        "he": "Hebrew",
        "hi": "Hindi",
        "hr": "Croatian",
        "ht": "Haitian Creole",
        "hu": "Hungarian",
        "hy": "Armenian",
        "id": "Indonesian",
        "ig": "Igbo",
        "is": "Icelandic",
        "it": "Italian",
        "ja": "Japanese",
        "jw": "Javanese",
        "ka": "Georgian",
        "kk": "Kazakh",
        "km": "Khmer",
        "kn": "Kannada",
        "ko": "Korean",
        "ku": "Kurdish",
        "ky": "Kyrgyz",
        "la": "Latin",
        "lb": "Luxembourgish",
        "ln": "Lingala",
        "lo": "Lao",
        "lt": "Lithuanian",
        "lv": "Latvian",
        "mg": "Malagasy",
        "mi": "Maori",
        "mk": "Macedonian",
        "ml": "Malayalam",
        "mn": "Mongolian",
        "mr": "Marathi",
        "ms": "Malay",
        "mt": "Maltese",
        "my": "Myanmar",
        "ne": "Nepali",
        "nl": "Dutch",
        "nn": "Norwegian Nynorsk",
        "no": "Norwegian",
        "oc": "Occitan",
        "or": "Odia",
        "pa": "Punjabi",
        "pl": "Polish",
        "ps": "Pashto",
        "pt": "Portuguese",
        "ro": "Romanian",
        "ru": "Russian",
        "sa": "Sanskrit",
        "sd": "Sindhi",
        "si": "Sinhala",
        "sk": "Slovak",
        "sl": "Slovenian",
        "sn": "Shona",
        "so": "Somali",
        "sq": "Albanian",
        "sr": "Serbian",
        "su": "Sundanese",
        "sv": "Swedish",
        "sw": "Swahili",
        "ta": "Tamil",
        "te": "Telugu",
        "tg": "Tajik",
        "th": "Thai",
        "tk": "Turkmen",
        "tl": "Tagalog",
        "tr": "Turkish",
        "tt": "Tatar",
        "uk": "Ukrainian",
        "ur": "Urdu",
        "uz": "Uzbek",
        "vi": "Vietnamese",
        "wo": "Wolof",
        "xh": "Xhosa",
        "yi": "Yiddish",
        "yo": "Yoruba",
        "yue": "Cantonese",
        "zh": "Chinese",
        "zu": "Zulu"
    ]
}
