import Foundation


@MainActor
class WhisperPrompt: ObservableObject {
    @Published var transcriptionPrompt: String = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
    
    private let customPromptsKey = "CustomLanguagePrompts"
    
    // Store user-customized prompts
    private var customPrompts: [String: String] = [:]
    
    // Language-specific base prompts.
    //
    // El `initial_prompt` de Whisper sirve como "calibración" del modelo:
    // una frase corta que le indica el idioma esperado y el vocabulario
    // común. Para idiomas donde los hablantes mezclan inglés tech (código,
    // productos, herramientas) — ES, PT, FR, DE, IT — incluimos ejemplos
    // del code-switching más típico para que Whisper no malinterprete
    // palabras como "download", "meeting", "deploy", "frontend" como
    // intentos fonéticos de palabras locales.
    //
    // Notar: Whisper detecta idioma por audio, no por este prompt. Pero
    // cuando el chunk es ambiguo o tiene jerga técnica, el prompt baja
    // la perplejidad y mejora la elección de tokens.
    private let languagePrompts: [String: String] = [
        // English — sample con vocabulario tech común
        "en": "Hello, how are you doing? Let me download the file and deploy the frontend.",

        // Asian Languages
        "hi": "नमस्ते, कैसे हैं आप? आपसे मिलकर अच्छा लगा।",
        "bn": "নমস্কার, কেমন আছেন? আপনার সাথে দেখা হয়ে ভালো লাগলো।",
        "ja": "こんにちは、お元気ですか？お会いできて嬉しいです。",
        "ko": "안녕하세요, 잘 지내시나요? 만나서 반갑습니다.",
        "zh": "你好，最近好吗？见到你很高兴。",
        "th": "สวัสดีครับ/ค่ะ, สบายดีไหม? ยินดีที่ได้พบคุณ",
        "vi": "Xin chào, bạn khỏe không? Rất vui được gặp bạn.",
        "yue": "你好，最近點呀？見到你好開心。",

        // European Languages — code-switching ES/PT/FR/DE/IT con inglés tech
        "es": "Hola, ¿cómo estás? Tengo un meeting a las 3 con el team sobre el bug del frontend. Voy a hacer el deploy después del download.",
        "fr": "Bonjour, comment allez-vous? J'ai un meeting à 3 heures avec le team sur le bug du frontend.",
        "de": "Hallo, wie geht es dir? Ich habe ein Meeting um 3 mit dem Team über den Bug im Frontend.",
        "it": "Ciao, come stai? Ho un meeting alle 3 con il team sul bug del frontend.",
        "pt": "Olá, como você está? Tenho um meeting às 3 com o team sobre o bug do frontend. Vou fazer o deploy depois do download.",
        "ru": "Здравствуйте, как ваши дела? Приятно познакомиться.",
        "pl": "Cześć, jak się masz? Miło cię poznać.",
        "nl": "Hallo, hoe gaat het? Aangenaam kennis te maken.",
        "tr": "Merhaba, nasılsın? Tanıştığımıza memnun oldum.",
        
        // Middle Eastern Languages
        "ar": "مرحباً، كيف حالك؟ سعيد بلقائك.",
        "fa": "سلام، حال شما چطور است؟ از آشنایی با شما خوشوقتم.",
        "he": ",שלום, מה שלומך? נעים להכיר",
        
        // South Asian Languages
        "ta": "வணக்கம், எப்படி இருக்கிறீர்கள்? உங்களை சந்தித்ததில் மகிழ்ச்சி.",
        "te": "నమస్కారం, ఎలా ఉన్నారు? కలవడం చాలా సంతోషం.",
        "ml": "നമസ്കാരം, സുഖമാണോ? കണ്ടതിൽ സന്തോഷം.",
        "kn": "ನಮಸ್ಕಾರ, ಹೇಗಿದ್ದೀರಾ? ನಿಮ್ಮನ್ನು ಭೇಟಿಯಾಗಿ ಸಂತೋಷವಾಗಿದೆ.",
        "ur": "السلام علیکم، کیسے ہیں آپ؟ آپ سے مل کر خوشی ہوئی۔",
        
        // Default prompt for unsupported languages
        "default": ""
    ]
    
    init() {
        loadCustomPrompts()
        updateTranscriptionPrompt()
        
        // Setup notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleLanguageChange() {
        updateTranscriptionPrompt()
    }
    
    private func loadCustomPrompts() {
        if let savedPrompts = UserDefaults.standard.dictionary(forKey: customPromptsKey) as? [String: String] {
            customPrompts = savedPrompts
        }
    }
    
    private func saveCustomPrompts() {
        UserDefaults.standard.set(customPrompts, forKey: customPromptsKey)
        UserDefaults.standard.synchronize() // Force immediate synchronization
    }
    
    func updateTranscriptionPrompt() {
        // Get the currently selected language from UserDefaults
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        
        // Get the prompt for the selected language (custom if available, otherwise default)
        let basePrompt = getLanguagePrompt(for: selectedLanguage)
        let prompt = basePrompt.isEmpty ? "" : basePrompt
        
        transcriptionPrompt = prompt
        UserDefaults.standard.set(prompt, forKey: "TranscriptionPrompt")
        UserDefaults.standard.synchronize() // Force immediate synchronization
        
        // Notify that the prompt has changed
        NotificationCenter.default.post(name: .promptDidChange, object: nil)
    }
    
    func getLanguagePrompt(for language: String) -> String {
        // First check if there's a custom prompt for this language
        if let customPrompt = customPrompts[language], !customPrompt.isEmpty {
            return customPrompt
        }
        
        // Otherwise return the default prompt, with safe fallback
        return languagePrompts[language] ?? languagePrompts["default"] ?? ""
    }
    
    func setCustomPrompt(_ prompt: String, for language: String) {
        customPrompts[language] = prompt
        saveCustomPrompts()
        updateTranscriptionPrompt()
        
        // Force update the UI
        objectWillChange.send()
    }
}
