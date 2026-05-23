import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
}

enum AppText {
    static func t(_ key: String, language rawLanguage: String) -> String {
        guard rawLanguage == AppLanguage.spanish.rawValue else {
            return key
        }

        return spanish[key] ?? key
    }

    private static let spanish: [String: String] = [
        "Dashboard": "Panel",
        "Transcribe Audio": "Transcribir audio",
        "History": "Historial",
        "AI Models": "Modelos de IA",
        "Enhancement": "Mejora",
        "Power Mode": "Modo Power",
        "Permissions": "Permisos",
        "Audio Input": "Entrada de audio",
        "Dictionary": "Diccionario",
        "Settings": "Configuración",
        "Nexo Whisper Pro": "Nexo Whisper Pro",
        "Select a view": "Seleccioná una vista",

        "App Language": "Idioma de la app",
        "Shortcuts": "Atajos",
        "Primary Shortcut": "Atajo principal",
        "Secondary Shortcut": "Atajo secundario",
        "Add Second Shortcut": "Agregar segundo atajo",
        "Additional Shortcuts": "Atajos adicionales",
        "Paste Last Transcription (Original)": "Pegar última transcripción (original)",
        "Paste Last Transcription (Enhanced)": "Pegar última transcripción (mejorada)",
        "Retry Last Transcription": "Reintentar última transcripción",
        "Cancel Recording": "Cancelar grabación",
        "Reset to default": "Restablecer valor predeterminado",
        "Middle-Click Recording": "Grabar con clic medio",
        "Activation Delay": "Demora de activación",
        "Recording Feedback": "Feedback de grabación",
        "Sound Feedback": "Sonidos de feedback",
        "Mute Audio While Recording": "Silenciar audio al grabar",
        "Resume Delay": "Demora para reanudar",
        "Keep Clipboard Content": "Conservar portapapeles",
        "Restore Delay": "Demora para restaurar",
        "Paste Method": "Método de pegado",
        "Interface": "Interfaz",
        "Recorder Style": "Estilo del grabador",
        "Experimental": "Experimental",
        "Pause Media While Recording": "Pausar multimedia al grabar",
        "General": "General",
        "Hide Dock Icon": "Ocultar icono del Dock",
        "Auto-check Updates": "Buscar actualizaciones automáticamente",
        "Show Announcements": "Mostrar anuncios",
        "Check for Updates": "Buscar actualizaciones",
        "Reset Onboarding": "Reiniciar introducción",
        "Privacy": "Privacidad",
        "Backup": "Respaldo",
        "Export Settings": "Exportar configuración",
        "Import Settings": "Importar configuración",
        "Export": "Exportar",
        "Import": "Importar",
        "Diagnostics": "Diagnóstico",
        "Cancel": "Cancelar",
        "Reset": "Reiniciar",
        "Got it": "Entendido",
        "Power Mode Still Active": "Modo Power todavía activo",
        "Disable or remove your Power Modes first.": "Primero desactivá o eliminá tus modos Power.",
        "Persist Configured Preferences": "Mantener preferencias configuradas",
        "Control how Nexo Whisper handles your transcription data and audio recordings.": "Controlá cómo Nexo Whisper maneja tus transcripciones y grabaciones de audio.",
        "Export all settings, or choose specific categories when importing a backup.": "Exportá toda la configuración o elegí categorías específicas al importar un respaldo.",
        "You'll see the introduction screens again the next time you launch the app.": "Vas a ver las pantallas de introducción otra vez la próxima vez que abras la app.",
        "Apply custom settings based on active app or website.": "Aplicá configuraciones personalizadas según la app o sitio web activo.",
        "When enabled, Power Mode preferences stay active after you stop recording instead of reverting to your original preferences. They will only change when a different Power Mode activates.": "Cuando está activo, las preferencias del Modo Power siguen aplicadas después de grabar en vez de volver a tus preferencias originales. Solo cambian cuando se activa otro Modo Power.",
        "Pauses playing media when recording starts and resumes when done.": "Pausa la reproducción multimedia al empezar a grabar y la reanuda al terminar.",
        "Nexo Whisper temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay. When disabled, the pasted transcription stays on your clipboard.": "Nexo Whisper usa temporalmente el portapapeles para pegar la transcripción. Si está activo, restaura el contenido anterior después de la demora seleccionada. Si está apagado, la transcripción pegada queda en el portapapeles.",
        "Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly.": "El método predeterminado simula Cmd+V. AppleScript puede ayudar cuando algunos layouts de teclado no pegan correctamente."
    ]
}
