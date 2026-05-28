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

        // 3. Intentar leer texto seleccionado del elemento focuseado
        ctx.selectedText = focusedSelectedText()

        // 4. Intentar leer el elemento bajo el cursor (técnica del otro agente)
        if let (text, role) = elementTextAt(point: cursorLocation) {
            ctx.elementText = text
            ctx.role = role
        }

        logger.info("Extracted: \(ctx.debugDescription)")
        return ctx
    }

    // ── Técnica 1: texto seleccionado en el elemento focuseado ──────────

    private static func focusedSelectedText() -> String? {
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

        if selResult == .success,
           let text = selectedText as? String,
           !text.isEmpty {
            return text
        }
        return nil
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

    // ── Técnica 3: clipboard fallback (último recurso) ──────────────────

    /// Si las técnicas AX fallan, este método simula Cmd+C y lee el
    /// pasteboard, preservando el contenido previo.
    /// NOTA: ya hay una implementación parecida en `ClipboardManager` para
    /// el pipeline normal — la podríamos reutilizar en F2. Por ahora dejamos
    /// el método como stub para no duplicar el code path.
    static func clipboardFallback() -> String? {
        // TODO(F2): integrar con ClipboardManager existente
        logger.debug("Clipboard fallback not yet implemented")
        return nil
    }
}
