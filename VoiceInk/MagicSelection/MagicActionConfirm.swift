import AppKit
import SwiftUI

/// Confirmación editable antes de ejecutar una acción (crear evento / nota /
/// recordatorio / mail). Maxi: que muestre los datos preseleccionados, uno
/// revisa, edita si hace falta y da OK. En macOS no hay editor modal del
/// sistema (EKEventEditViewController es iOS), así que mostramos un mini-form
/// propio en una ventana flotante.
@MainActor
final class MagicActionConfirmer {
    static let shared = MagicActionConfirmer()
    private var window: NSWindow?

    /// ¿Confirmar antes de crear? (preferencia, default ON.)
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "magicSelection.confirmActions") as? Bool ?? true
    }

    func confirm(tool: String,
                 params: [String: String],
                 content: String,
                 onConfirm: @escaping (_ tool: String, _ params: [String: String], _ content: String) -> Void) {

        let lines = content.components(separatedBy: "\n")
        let draftTitle = params["title"] ?? (lines.first ?? content)
        let draftBody: String = {
            if tool == "mail" { return content }
            return lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : ""
        }()

        let view = MagicActionConfirmView(
            tool: tool,
            initialTitle: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            initialBody: draftBody.trimmingCharacters(in: .whitespacesAndNewlines),
            initialSubject: params["subject"] ?? "",
            initialDateISO: params["date"] ?? "",
            onCancel: { [weak self] in self?.close() },
            onConfirm: { [weak self] title, body, subject, dateISO in
                self?.close()
                var p = params
                p["title"] = title
                if !subject.isEmpty { p["subject"] = subject }
                if !dateISO.isEmpty { p["date"] = dateISO }
                let finalContent = tool == "mail" ? body
                    : (body.isEmpty ? title : "\(title)\n\(body)")
                onConfirm(tool, p, finalContent)
            }
        )

        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable]
        win.title = "Confirmar acción"
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct MagicActionConfirmView: View {
    let tool: String
    @State var title: String
    @State var bodyText: String
    @State var subject: String
    @State var dateISO: String
    let onCancel: () -> Void
    let onConfirm: (_ title: String, _ body: String, _ subject: String, _ dateISO: String) -> Void

    init(tool: String, initialTitle: String, initialBody: String,
         initialSubject: String, initialDateISO: String,
         onCancel: @escaping () -> Void,
         onConfirm: @escaping (String, String, String, String) -> Void) {
        self.tool = tool
        _title = State(initialValue: initialTitle)
        _bodyText = State(initialValue: initialBody)
        _subject = State(initialValue: initialSubject)
        _dateISO = State(initialValue: initialDateISO)
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    private var meta: (icon: String, name: String) {
        switch tool {
        case "calendar": return ("calendar", "Evento de Calendario")
        case "reminders": return ("checklist", "Recordatorio")
        case "mail": return ("envelope", "Mail")
        default: return ("note.text", "Nota")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(meta.name, systemImage: meta.icon).font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(tool == "mail" ? "Asunto" : "Título").font(.caption).foregroundStyle(.secondary)
                TextField("", text: tool == "mail" ? $subject : $title)
                    .textFieldStyle(.roundedBorder)
            }

            if tool == "calendar" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fecha y hora (AAAA-MM-DDTHH:mm, vacío = ajustar después)")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("2026-06-15T10:00", text: $dateISO)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tool == "mail" ? "Cuerpo" : (tool == "calendar" || tool == "reminders" ? "Notas" : "Contenido"))
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $bodyText)
                    .font(.system(size: 12))
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.3)))
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Crear") {
                    onConfirm(title.trimmingCharacters(in: .whitespacesAndNewlines),
                              bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                              subject.trimmingCharacters(in: .whitespacesAndNewlines),
                              dateISO.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
