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
    static let supportedTools = ["notes", "mail", "reminders", "calendar",
                                 "maps", "message", "call", "shortcut"]

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
        case "maps":
            return openMaps(params["query"] ?? body)
        case "message", "whatsapp", "telegram":
            return sendMessage(body, forceApp: tool == "message" ? nil : tool.lowercased())
        case "call", "phone":
            return call(params["number"] ?? body)
        case "shortcut", "atajo":
            return runShortcut(name: params["name"] ?? "", input: body)
        default:
            logger.error("Acción desconocida: \(tool, privacy: .public)")
            return Outcome(success: false, message: String(localized: "I don't recognize that action."), appName: nil)
        }
    }

    // ── Maps / Mensajería / Llamada / Atajos ────────────────────────────

    @MainActor
    static func openMaps(_ query: String) -> Outcome {
        let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://maps.apple.com/?q=\(enc)") else {
            return Outcome(success: false, message: String(localized: "Couldn't open Maps."), appName: "Maps")
        }
        NSWorkspace.shared.open(url)
        return Outcome(success: true, message: String(localized: "Opening in Maps"), appName: "Maps")
    }

    /// App de mensajería por defecto (Settings) o forzada.
    static var messagingApp: String {
        UserDefaults.standard.string(forKey: "magicSelection.messagingApp") ?? "whatsapp"
    }

    @MainActor
    static func sendMessage(_ text: String, forceApp: String? = nil) -> Outcome {
        let app = forceApp ?? messagingApp
        let enc = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let (urlStr, name): (String, String) = {
            switch app {
            // El share URL de Telegram SÍ lleva el texto (tg://msg?text= no es fiable).
            case "telegram": return ("https://t.me/share/url?url=&text=\(enc)", "Telegram")
            case "imessage", "messages": return ("sms:&body=\(enc)", "iMessage")
            default: return ("https://wa.me/?text=\(enc)", "WhatsApp")
            }
        }()
        guard let url = URL(string: urlStr) else {
            return Outcome(success: false, message: String(localized: "Couldn't compose the message."), appName: name)
        }
        NSWorkspace.shared.open(url)
        return Outcome(success: true, message: String(localized: "Message ready in \(name)"), appName: name)
    }

    @MainActor
    static func call(_ number: String) -> Outcome {
        let clean = number.filter { "+0123456789".contains($0) }
        guard !clean.isEmpty, let url = URL(string: "tel:\(clean)") else {
            return Outcome(success: false, message: String(localized: "No number found to call."), appName: nil)
        }
        NSWorkspace.shared.open(url)
        return Outcome(success: true, message: String(localized: "Calling \(clean)…"), appName: nil)
    }

    @MainActor
    static func runShortcut(name: String, input: String) -> Outcome {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(success: false, message: String(localized: "You didn't tell me which Shortcut to run."), appName: "Shortcuts")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]
        let inPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            if let data = input.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            inPipe.fileHandleForWriting.closeFile()
            return Outcome(success: true, message: String(localized: "Shortcut “\(trimmed)” ran"), appName: "Shortcuts")
        } catch {
            logger.error("shortcuts run falló: \(error.localizedDescription, privacy: .public)")
            return Outcome(success: false, message: String(localized: "Couldn't run the shortcut."), appName: "Shortcuts")
        }
    }

    // ── Notas (AppleScript) ─────────────────────────────────────────────

    @MainActor
    private static func createNote(_ text: String) -> Outcome {
        guard !text.isEmpty else { return Outcome(success: false, message: String(localized: "Empty note."), appName: nil) }
        // Notes usa el primer renglón como título. Pasamos el texto como body.
        let escaped = appleScriptEscaped(text)
        let script = """
        tell application "Notes"
            make new note with properties {body:"\(escaped)"}
        end tell
        """
        if runAppleScript(script) {
            return Outcome(success: true, message: String(localized: "Added to Notes"), appName: "Notes")
        }
        return Outcome(success: false, message: String(localized: "Couldn't add to Notes (check Automation permissions)."), appName: "Notes")
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
            return Outcome(success: false, message: String(localized: "Couldn't compose the email."), appName: nil)
        }
        NSWorkspace.shared.open(url)
        return Outcome(success: true, message: String(localized: "Email ready to send"), appName: nil)
    }

    // ── Recordatorios (EventKit) ────────────────────────────────────────

    @MainActor
    private static func createReminder(_ text: String) async -> Outcome {
        guard !text.isEmpty else { return Outcome(success: false, message: String(localized: "Empty reminder."), appName: nil) }
        guard await requestReminderAccess() else {
            return Outcome(success: false, message: String(localized: "Reminders permission missing. Grant it in System Settings → Privacy."), appName: "Reminders")
        }
        guard let list = eventStore.defaultCalendarForNewReminders() else {
            return Outcome(success: false, message: String(localized: "No Reminders list available."), appName: "Reminders")
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
            return Outcome(success: true, message: String(localized: "Added to Reminders"), appName: "Reminders")
        } catch {
            logger.error("EventKit reminder falló: \(error.localizedDescription, privacy: .public)")
            return Outcome(success: false, message: String(localized: "Couldn't create the reminder."), appName: "Reminders")
        }
    }

    // ── Calendario (EventKit) ───────────────────────────────────────────

    @MainActor
    private static func createEvent(title: String, dateISO: String?) async -> Outcome {
        let summary = (title.components(separatedBy: "\n").first ?? title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return Outcome(success: false, message: String(localized: "Empty event."), appName: "Calendar")
        }
        guard await requestEventAccess() else {
            return Outcome(success: false, message: String(localized: "Calendar permission missing. Grant it in System Settings → Privacy."), appName: "Calendar")
        }
        guard let cal = eventStore.defaultCalendarForNewEvents else {
            return Outcome(success: false, message: String(localized: "No calendar available."), appName: "Calendar")
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
            let msg = hadDate ? String(localized: "Event added to Calendar") : String(localized: "Event created (adjust the date in Calendar)")
            return Outcome(success: true, message: msg, appName: "Calendar")
        } catch {
            logger.error("EventKit event falló: \(error.localizedDescription, privacy: .public)")
            return Outcome(success: false, message: String(localized: "Couldn't create the event."), appName: "Calendar")
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
