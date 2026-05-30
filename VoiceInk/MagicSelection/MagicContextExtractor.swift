import AppKit
import ApplicationServices
import Foundation
import OSLog

/// Extrae contexto del elemento bajo el cursor usando la Accessibility API.
///
/// Estrategia (en orden de prioridad):
/// 1. **Texto seleccionado** del elemento focuseado del sistema (lo que el
///    usuario marcó con el mouse o con Shift+arrow).
/// 2. **Texto del elemento bajo las coordenadas (X, Y)** del cursor — esto
///    funciona en Excel cells, Slack messages, web spans, etc.
/// 3. **Atributo `kAXValueAttribute`** del elemento (text fields, labels).
/// 4. **Fallback**: simular `Cmd+C` y leer NSPasteboard (preserva el
///    clipboard previo).
///
/// Devuelve un struct con todo el contexto disponible para que el AI
/// pueda decidir qué hacer.
struct MagicContext {
    /// Texto crudo extraído del elemento debajo del cursor.
    var elementText: String?
    /// Texto explícitamente seleccionado por el usuario (puede ser igual a
    /// elementText o más específico).
    var selectedText: String?
    /// Role de accessibility del elemento (button, textArea, link, etc.).
    var role: String?
    /// ¿La selección vino de un elemento EDITABLE? Determina si el resultado
    /// se REEMPLAZA (pega) o se MUESTRA en el panel. Se decide al capturar la
    /// selección (no por la posición del cursor al cerrar el wiggle).
    var isSelectionEditable: Bool = false
    /// Bundle ID de la app activa (ej. "com.apple.mail").
    var appBundleId: String?
    /// Nombre de la app activa (ej. "Mail").
    var appName: String?
    /// Coordenadas globales del cursor cuando se hizo la captura.
    var cursorLocation: NSPoint = .zero

    /// El "mejor" texto disponible para usar como contexto. Prioriza la
    /// selección del usuario; si no hay, usa el elemento bajo el cursor.
    var bestText: String? {
        if let sel = selectedText, !sel.isEmpty { return sel }
        if let el = elementText, !el.isEmpty { return el }
        return nil
    }

    /// Versión summary para debugging.
    var debugDescription: String {
        let text = bestText.map { $0.prefix(80) }.map(String.init) ?? "<nil>"
        return "MagicContext[app=\(appName ?? "?"), role=\(role ?? "?"), text=\"\(text)…\"]"
    }
}

enum MagicContextExtractor {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicContextExtractor"
    )

    /// Extrae contexto sincrónicamente. Llamar desde main thread.
    /// Tiene un timeout interno corto (AX puede colgarse con apps freezadas)
    /// para no bloquear el flujo de Magic Selection.
    static func extract(at cursorLocation: NSPoint) -> MagicContext {
        var ctx = MagicContext()
        ctx.cursorLocation = cursorLocation

        // 1. App activa
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            ctx.appBundleId = activeApp.bundleIdentifier
            ctx.appName = activeApp.localizedName
        }

        // 2. Necesitamos permiso AX para todo lo demás
        guard AXIsProcessTrusted() else {
            logger.warning("AX not trusted — Magic Selection needs Accessibility permission")
            return ctx
        }

        // 3. Intentar leer texto SELECCIONADO del elemento focuseado. La
        // selección manda y se captura del elemento focuseado, NO de la
        // posición del cursor — así no importa dónde termine el wiggle.
        if let (text, editable) = focusedSelectedText() {
            ctx.selectedText = text
            ctx.isSelectionEditable = editable
        }

        // 4. Intentar leer el elemento bajo el cursor (para "qué significa
        // esto" sobre algo NO seleccionado). Esto nunca se trata como editable.
        if let (text, role) = elementTextAt(point: cursorLocation) {
            ctx.elementText = text
            ctx.role = role
        }

        logger.info("Extracted: \(ctx.debugDescription)")
        return ctx
    }

    // ── Técnica 1: texto seleccionado en el elemento focuseado ──────────

    private static func focusedSelectedText() -> (text: String, editable: Bool)? {
        let systemElement = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusedResult == .success,
              let focusedElement = focused else {
            return nil
        }

        // swiftlint:disable:next force_cast
        let axElement = focusedElement as! AXUIElement

        var selectedText: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard selResult == .success,
              let text = selectedText as? String,
              !text.isEmpty else {
            return nil
        }

        // ¿El elemento focuseado es editable? (settable value o role editable)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
        let roleStr = (role as? String) ?? ""
        let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &settable)

        let editable = settable.boolValue || editableRoles.contains(roleStr)
        logger.info("focusedSelectedText: role=\(roleStr, privacy: .public) editable=\(editable)")
        return (text, editable)
    }

    // ── Técnica 2: leer el elemento bajo coords (X, Y) ──────────────────

    /// Devuelve (texto, role) del elemento bajo `point`, si se puede leer.
    private static func elementTextAt(point: NSPoint) -> (String, String)? {
        let systemElement = AXUIElementCreateSystemWide()

        // CGEvent coords y NSScreen coords difieren en el origen Y.
        // AXUIElementCopyElementAtPosition espera coords con origen
        // arriba-izquierda (CGWindow coords), pero el `point` que recibimos
        // viene en NSScreen coords (abajo-izquierda).
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let flippedY = primaryScreen.frame.height - point.y

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(point.x),
            Float(flippedY),
            &element
        )

        guard result == .success, let target = element else {
            return nil
        }

        // Leer role para diagnóstico
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(target, kAXRoleAttribute as CFString, &role)
        let roleString = (role as? String) ?? "AXUnknown"

        // Intentar varios attributes en orden de utilidad
        let attributesToTry: [CFString] = [
            kAXValueAttribute as CFString,            // text fields, labels
            kAXSelectedTextAttribute as CFString,     // selección actual
            kAXTitleAttribute as CFString,            // buttons, links
            kAXDescriptionAttribute as CFString,      // a11y labels
            kAXHelpAttribute as CFString              // tooltips
        ]

        for attr in attributesToTry {
            var value: CFTypeRef?
            let attrResult = AXUIElementCopyAttributeValue(target, attr, &value)
            if attrResult == .success,
               let text = value as? String,
               !text.isEmpty {
                return (text, roleString)
            }
        }

        return nil
    }

    // ── ¿Hay un campo editable bajo el cursor? ──────────────────────────

    /// Decide si el elemento BAJO EL CURSOR es un campo de texto editable.
    /// Se usa para elegir entre REEMPLAZAR (pegar) o MOSTRAR en el panel.
    ///
    /// Criterio ESTRICTO y basado en la posición del MOUSE (no en el foco de
    /// teclado): en apps como Claude Code/terminales/Electron, el foco de
    /// teclado está en el input aunque la selección esté en un output de solo
    /// lectura. Ante la duda → NO editable (mejor mostrar el panel que pegar
    /// en el lugar equivocado).
    @MainActor
    static func isEditableUnderCursor(at point: NSPoint) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let systemElement = AXUIElementCreateSystemWide()
        guard let primaryScreen = NSScreen.screens.first else { return false }
        let flippedY = primaryScreen.frame.height - point.y

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemElement, Float(point.x), Float(flippedY), &element
        )
        guard result == .success, let target = element else { return false }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(target, kAXRoleAttribute as CFString, &role)
        let roleStr = (role as? String) ?? ""

        // Roles claramente NO editables → panel.
        let nonEditable: Set<String> = [
            "AXStaticText", "AXImage", "AXButton", "AXLink",
            "AXMenuItem", "AXHeading", "AXCell"
        ]
        if nonEditable.contains(roleStr) {
            logger.info("isEditableUnderCursor: role=\(roleStr, privacy: .public) → NO editable")
            return false
        }

        // Roles claramente editables → pegar.
        let editable: Set<String> = [
            "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"
        ]
        if editable.contains(roleStr) {
            logger.info("isEditableUnderCursor: role=\(roleStr, privacy: .public) → editable")
            return true
        }

        // Ambiguo (AXGroup, AXUnknown, AXWebArea, etc.): solo editable si el
        // value es realmente escribible (settable).
        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            target, kAXValueAttribute as CFString, &settable
        )
        let isSettable = settableResult == .success && settable.boolValue
        logger.info("isEditableUnderCursor: role=\(roleStr, privacy: .public) settable=\(isSettable) → \(isSettable ? "editable" : "NO editable")")
        return isSettable
    }

    // ── Técnica 4: clipboard fallback (Chrome, Electron, terminales) ────

    /// Cuando AX no expone texto (típico en Chrome/Chromium, Electron y
    /// algunas terminales — NO construyen el árbol de accesibilidad para el
    /// contenido web), capturamos la SELECCIÓN del usuario simulando Cmd+C y
    /// leyendo el pasteboard. Restaura el contenido previo del clipboard para
    /// no pisar lo que el usuario tuviera copiado.
    ///
    /// Requiere que el usuario YA tenga algo seleccionado. Es async porque
    /// hay que esperar a que el Cmd+C sintético populé el pasteboard.
    @MainActor
    static func clipboardSelection() async -> String? {
        guard AXIsProcessTrusted() else {
            logger.warning("Clipboard fallback necesita permiso AX para simular Cmd+C")
            return nil
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let saved = snapshotPasteboard(pasteboard)

        postCopyCommand()

        // Esperar a que el Cmd+C populé el pasteboard (cambia el changeCount),
        // con timeout para no colgar el flujo si no había nada seleccionado.
        let deadline = Date().addingTimeInterval(0.4)
        while pasteboard.changeCount == previousChangeCount, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        let copied = pasteboard.string(forType: .string)

        // Restaurar el clipboard previo del usuario.
        restorePasteboard(pasteboard, snapshot: saved)

        if let text = copied, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.info("Clipboard fallback capturó \(text.count) chars")
            return text
        }
        logger.info("Clipboard fallback: no se capturó texto (¿nada seleccionado?)")
        return nil
    }

    /// Simula Cmd+C vía CGEvent sin tocar el input source activo. Mismo
    /// patrón que `CursorPaster.pasteFromClipboard` pero con la tecla C
    /// (virtualKey 0x08) en vez de V.
    @MainActor
    private static func postCopyCommand() {
        let source = CGEventSource(stateID: .privateState)
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.error("No pude crear los eventos de Cmd+C")
            return
        }
        cmdDown.flags = .maskCommand
        cDown.flags = .maskCommand
        cUp.flags = .maskCommand
        cmdDown.post(tap: .cghidEventTap)
        cDown.post(tap: .cghidEventTap)
        cUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
    }

    private static func snapshotPasteboard(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private static func restorePasteboard(_ pb: NSPasteboard, snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }
}
