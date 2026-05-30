import AppKit
import EventKit
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

    /// Store de EventKit compartido (Calendario + Recordatorios).
    private static let eventStore = EKEventStore()

    @MainActor
    static func run(tool: String, params: [String: String], content: String) async -> Outcome {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tool.lowercased() {
        case "notes":
            return createNote(body)
        case "mail":
            return createMail(subject: params["subject"], body: body)
        case "reminders", "reminder":
            return await createReminder(body)
        case "calendar", "calendario", "event":
            return await createEvent(title: params["title"] ?? body, dateISO: params["date"])
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

    // ── Recordatorios (EventKit) ────────────────────────────────────────

    @MainActor
    private static func createReminder(_ text: String) async -> Outcome {
        guard !text.isEmpty else { return Outcome(success: false, message: "Recordatorio vacío.", appName: nil) }
        guard await requestReminderAccess() else {
            return Outcome(success: false, message: "Falta permiso de Recordatorios. Concedelo en Ajustes del sistema → Privacidad.", appName: "Reminders")
        }
        guard let list = eventStore.defaultCalendarForNewReminders() else {
            return Outcome(success: false, message: "No hay una lista de Recordatorios disponible.", appName: "Reminders")
        }
        let reminder = EKReminder(eventStore: eventStore)
        // Primera línea = título; el resto (si hay) van como nota.
        let lines = text.components(separatedBy: "\n")
        reminder.title = lines.first ?? text
        if lines.count > 1 {
            reminder.notes = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        reminder.calendar = list
        do {
            try eventStore.save(reminder, commit: true)
            return Outcome(success: true, message: "Agregado a Recordatorios", appName: "Reminders")
        } catch {
            logger.error("EventKit reminder falló: \(error.localizedDescription, privacy: .public)")
            return Outcome(success: false, message: "No pude crear el recordatorio.", appName: "Reminders")
        }
    }

    // ── Calendario (EventKit) ───────────────────────────────────────────

    @MainActor
    private static func createEvent(title: String, dateISO: String?) async -> Outcome {
        let summary = (title.components(separatedBy: "\n").first ?? title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return Outcome(success: false, message: "Evento vacío.", appName: "Calendar")
        }
        guard await requestEventAccess() else {
            return Outcome(success: false, message: "Falta permiso de Calendario. Concedelo en Ajustes del sistema → Privacidad.", appName: "Calendar")
        }
        guard let cal = eventStore.defaultCalendarForNewEvents else {
            return Outcome(success: false, message: "No hay un calendario disponible.", appName: "Calendar")
        }
        // Con fecha → la usamos; sin fecha → placeholder (hoy + 1h) para ajustar.
        let hadDate = parseDate(dateISO) != nil
        let start = parseDate(dateISO)
            ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ?? Date()
        let event = EKEvent(eventStore: eventStore)
        event.title = summary
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.calendar = cal
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            let msg = hadDate ? "Evento agregado al Calendario" : "Evento creado (ajustá la fecha en Calendario)"
            return Outcome(success: true, message: msg, appName: "Calendar")
        } catch {
            logger.error("EventKit event falló: \(error.localizedDescription, privacy: .public)")
            return Outcome(success: false, message: "No pude crear el evento.", appName: "Calendar")
        }
    }

    // ── Permisos EventKit ───────────────────────────────────────────────

    private static func requestReminderAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await eventStore.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { cont in
                eventStore.requestAccess(to: .reminder) { granted, _ in cont.resume(returning: granted) }
            }
        }
    }

    private static func requestEventAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { cont in
                eventStore.requestAccess(to: .event) { granted, _ in cont.resume(returning: granted) }
            }
        }
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
