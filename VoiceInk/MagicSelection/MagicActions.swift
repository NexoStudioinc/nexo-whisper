import AppKit
import Foundation
import OSLog

/// Acciones del sistema que Magic puede ejecutar sobre el resultado: agregar a
/// Notas, crear un mail, crear un recordatorio. La IA decide cuándo (header
/// `@@ACTION|tool=…@@`) y devuelve el contenido; acá se ejecuta.
///
/// Diseño de seguridad: solo apps de productividad (no mueve plata, no borra
/// nada). Mail usa `mailto:` (sin permisos). Notas/Recordatorios usan
/// AppleScript (macOS pide permiso de Automation la primera vez).
enum MagicActions {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicActions"
    )

    /// Resultado de ejecutar una acción: mensaje de confirmación para el usuario.
    struct Outcome {
        let success: Bool
        /// Texto corto para el toast (ej. "Agregado a Notas").
        let message: String
        /// Nombre legible de la app para el botón "Abrir …".
        let appName: String?
    }

    /// Acciones soportadas (lo que el LLM puede pedir en `tool=`).
    static let supportedTools = ["notes", "mail", "reminders", "calendar"]

    @MainActor
    static func run(tool: String, params: [String: String], content: String) -> Outcome {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tool.lowercased() {
        case "notes":
            return createNote(body)
        case "mail":
            return createMail(subject: params["subject"], body: body)
        case "reminders", "reminder":
            return createReminder(body)
        case "calendar", "calendario", "event":
            return createEvent(title: params["title"] ?? body, dateISO: params["date"])
        default:
            logger.error("Acción desconocida: \(tool, privacy: .public)")
            return Outcome(success: false, message: "No reconozco esa acción.", appName: nil)
        }
    }

    // ── Notas (AppleScript) ─────────────────────────────────────────────

    @MainActor
    private static func createNote(_ text: String) -> Outcome {
        guard !text.isEmpty else { return Outcome(success: false, message: "Nota vacía.", appName: nil) }
        // Notes usa el primer renglón como título. Pasamos el texto como body.
        let escaped = appleScriptEscaped(text)
        let script = """
        tell application "Notes"
            make new note with properties {body:"\(escaped)"}
        end tell
        """
        if runAppleScript(script) {
            return Outcome(success: true, message: "Agregado a Notas", appName: "Notes")
        }
        return Outcome(success: false, message: "No pude agregar a Notas (revisá permisos de Automatización).", appName: "Notes")
    }

    // ── Mail (mailto: — sin permisos) ───────────────────────────────────

    @MainActor
    private static func createMail(subject: String?, body: String) -> Outcome {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = ""
        var items: [URLQueryItem] = []
        if let subject, !subject.isEmpty { items.append(URLQueryItem(name: "subject", value: subject)) }
        if !body.isEmpty { items.append(URLQueryItem(name: "body", value: body)) }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else {
            return Outcome(success: false, message: "No pude armar el mail.", appName: nil)
        }
        NSWorkspace.shared.open(url)
        return Outcome(success: true, message: "Mail listo para enviar", appName: nil)
    }

    // ── Recordatorios (AppleScript) ─────────────────────────────────────

    @MainActor
    private static func createReminder(_ text: String) -> Outcome {
        guard !text.isEmpty else { return Outcome(success: false, message: "Recordatorio vacío.", appName: nil) }
        // El recordatorio toma como nombre la primera línea.
        let name = text.components(separatedBy: "\n").first ?? text
        let escaped = appleScriptEscaped(name)
        let script = """
        tell application "Reminders"
            make new reminder with properties {name:"\(escaped)"}
        end tell
        """
        if runAppleScript(script) {
            return Outcome(success: true, message: "Agregado a Recordatorios", appName: "Reminders")
        }
        return Outcome(success: false, message: "No pude agregar a Recordatorios (revisá permisos de Automatización).", appName: "Reminders")
    }

    // ── Calendario (AppleScript) ────────────────────────────────────────

    @MainActor
    private static func createEvent(title: String, dateISO: String?) -> Outcome {
        let summary = (title.components(separatedBy: "\n").first ?? title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return Outcome(success: false, message: "Evento vacío.", appName: "Calendar")
        }
        // Con fecha → la usamos; sin fecha → placeholder (hoy + 1h) para que el
        // usuario la ajuste en Calendario.
        let hadDate = parseDate(dateISO) != nil
        let date = parseDate(dateISO)
            ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ?? Date()
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let escaped = appleScriptEscaped(summary)
        // Construimos la fecha por componentes (robusto, sin depender del locale
        // de parsing de AppleScript).
        let script = """
        set theStart to (current date)
        set year of theStart to \(c.year ?? 2026)
        set month of theStart to \(c.month ?? 1)
        set day of theStart to \(c.day ?? 1)
        set hours of theStart to \(c.hour ?? 9)
        set minutes of theStart to \(c.minute ?? 0)
        set seconds of theStart to 0
        set theEnd to theStart + (60 * 60)
        tell application "Calendar"
            tell calendar 1
                make new event with properties {summary:"\(escaped)", start date:theStart, end date:theEnd}
            end tell
        end tell
        """
        if runAppleScript(script) {
            let msg = hadDate ? "Evento agregado al Calendario" : "Evento creado (ajustá la fecha en Calendario)"
            return Outcome(success: true, message: msg, appName: "Calendar")
        }
        return Outcome(success: false, message: "No pude crear el evento (revisá permisos de Automatización).", appName: "Calendar")
    }

    /// Parsea una fecha ISO o formato común. nil si no hay fecha válida.
    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let raw = s.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let formats = ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
        for f in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    @MainActor
    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript falló: \(String(describing: error), privacy: .public)")
            return false
        }
        return true
    }

    /// Escapa comillas y backslashes para meter texto en un literal AppleScript.
    private static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Abre una app por nombre (para el botón "Abrir …" tras una acción).
    @MainActor
    static func openApp(named appName: String) {
        let script = "tell application \"\(appName)\" to activate"
        runAppleScript(script)
    }
}
