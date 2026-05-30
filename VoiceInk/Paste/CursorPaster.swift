import Foundation
import AppKit
import Carbon
import os

class CursorPaster {
    private typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted
        /// No había text field con foco para recibir el paste. El texto
        /// quedó copiado en el clipboard (persistente) como fallback.
        /// El usuario puede pegarlo manualmente con Cmd+V donde quiera.
        case noTextFieldFocused

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    private static let prePasteDelay: TimeInterval = 0.10
    private static let pasteShortcutEventDelay: TimeInterval = 0.01
    private static let minimumClipboardRestoreDelay: TimeInterval = 0.25

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String) -> Task<PasteResult, Never> {
        Task { @MainActor in
            await performPasteSession(text)
        }
    }

    /// Pega `text` REACTIVANDO primero la app de origen (por PID). Pensado para
    /// Magic Selection: cuando capturamos la selección en Chrome/Electron (que
    /// no exponen su árbol AX) o cuando el panel de respuesta se interpuso, el
    /// foco puede haberse movido. Traer la app de origen al frente antes del
    /// Cmd+V garantiza que el pegado caiga donde el usuario lo espera.
    ///
    /// Si `appPID` es nil o la app ya está activa, se comporta como un paste
    /// normal (no roba foco innecesariamente).
    ///
    /// `force`: si es true, saltea la detección de campo de texto y pega sí o sí
    /// (Cmd+V). Pensado para el botón "Reemplazar" del panel, donde el usuario
    /// YA decidió pegar — en Chrome/Electron la detección AX suele fallar y no
    /// queremos que el texto termine en el clipboard en vez de pegarse.
    @MainActor
    static func pasteReactivating(_ text: String, appPID: pid_t?, force: Bool = false) {
        Task { @MainActor in
            if let pid = appPID,
               let app = NSRunningApplication(processIdentifier: pid),
               !app.isActive {
                app.activate()
                // Darle tiempo a venir al frente antes de postear el Cmd+V,
                // sino el evento iría a la app equivocada.
                await wait(0.18)
            }
            _ = await performPasteSession(text, skipFocusCheck: force)
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    @MainActor
    private static func performPasteSession(_ text: String, skipFocusCheck: Bool = false) async -> PasteResult {
        // Fallback: si no hay text field con foco, evitamos el Cmd+V (iría a
        // la nada o a un botón random) y dejamos el texto en clipboard como
        // persistente para que el usuario pueda hacerlo manualmente.
        // `skipFocusCheck` lo saltea cuando el usuario pidió pegar explícitamente.
        if !skipFocusCheck, !hasFocusedTextInputField() {
            logger.notice("No text input focused — saving transcription to clipboard as fallback")
            // Fix defensivo (reporte usuario: a veces la primera escritura
            // del clipboard se pierde y solo aparece tras la segunda grabación).
            // Causa raíz no confirmada — sospechas: apps de clipboard manager
            // (Maccy, Paste, Raycast) interceptando markers; o un race con el
            // restore de la sesión anterior. Solución: escribimos dos veces
            // con un pequeño delay para sobrevivir a cualquiera de esos casos.
            _ = ClipboardManager.setClipboard(text, transient: false, sessionID: nil)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                _ = ClipboardManager.setClipboard(text, transient: false, sessionID: nil)
            }
            return .noTextFieldFocused
        }

        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
        let sessionID = UUID().uuidString

        guard ClipboardManager.setClipboard(
            text,
            transient: shouldRestoreClipboard,
            sessionID: shouldRestoreClipboard ? sessionID : nil
        ) else {
            logger.error("Failed to prepare clipboard for paste")
            return .commandNotPosted
        }

        await wait(prePasteDelay)

        let pasteResult = await postPasteCommand()
        if shouldRestoreClipboard {
            scheduleClipboardRestore(
                savedContents,
                expectedText: text,
                sessionID: sessionID,
                on: pasteboard
            )
        }

        return pasteResult
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        }
    }

    @MainActor
    private static func postPasteCommand() async -> PasteResult {
        if PasteMethod.current() == .appleScript {
            return pasteUsingAppleScript() ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard()
        }
    }

    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard
    ) {
        let delay = max(
            UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
            minimumClipboardRestoreDelay
        )

        Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID) else {
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText &&
            pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
    }

    private static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }

    // MARK: - AppleScript paste

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript("tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode   = makeScript("tell application \"System Events\" to key code 9 using command down")

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript() -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("AppleScript paste script is unavailable")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript paste failed: \(String(describing: error), privacy: .public)")
        }
        return error == nil
    }

    // MARK: - Focus detection (fallback to clipboard)

    /// Devuelve true si tiene sentido pegar acá. Por default es PERMISIVO:
    /// asume que sí (como hace el VoiceInk original), porque la detección
    /// vía Accessibility falla en muchas apps modernas (Notion, Cursor,
    /// web views, ChatGPT, Slack, etc.) que no exponen role estándar.
    ///
    /// Solo bloquea cuando está 100% seguro que el foco está en algo que NO
    /// es text input — específicamente cuando el role es explícitamente un
    /// elemento no-editable como `AXButton`, `AXMenuItem`, `AXStaticText`,
    /// `AXImage`, etc.
    @MainActor
    private static func hasFocusedTextInputField() -> Bool {
        guard AXIsProcessTrusted() else { return true }

        let systemElement = AXUIElementCreateSystemWide()
        // CRÍTICO: cap el tiempo de las queries AX a 0.5s para que si la app
        // target está colgada no freezeemos el main thread (lo que se siente
        // como la Mac "trabada" al apretar el shortcut). 500ms es generoso
        // para una query AX normal (típicamente <50ms).
        AXUIElementSetMessagingTimeout(systemElement, 0.5)
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        // Si el sistema no nos puede decir qué está focuseado, asumimos
        // que sí hay input — mejor pegar y que el usuario haga Cmd+Z si
        // se equivocó, que dejar el texto en clipboard sin avisar.
        guard result == .success, let focusedElement = focused else {
            return true
        }

        let element = focusedElement as! AXUIElement
        // Mismo timeout para queries sobre el elemento focuseado.
        AXUIElementSetMessagingTimeout(element, 0.5)

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = role as? String ?? ""

        // Lista negra: solo cuando estamos 100% seguros que no es input.
        let nonTextRoles: Set<String> = [
            "AXButton",
            "AXMenuButton",
            "AXMenuItem",
            "AXMenu",
            "AXMenuBar",
            "AXMenuBarItem",
            "AXImage",
            "AXStaticText",
            "AXCheckBox",
            "AXRadioButton",
            "AXSlider",
            "AXPopUpButton",
            "AXTabGroup",
            "AXToolbar",
            "AXDockItem"
        ]
        if nonTextRoles.contains(roleString) {
            return false
        }

        // Cualquier otro role (incluido vacío o desconocido) → asumimos input.
        return true
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard() async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to paste with simulated key events")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.error("Failed to create Cmd+V keyboard events")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags   = .maskCommand
        vUp.flags     = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vUp.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        cmdUp.post(tap: .cghidEventTap)

        return .commandPosted
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Auto Send Keys

    static func performAutoSend(_ key: AutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags   = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags   = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
