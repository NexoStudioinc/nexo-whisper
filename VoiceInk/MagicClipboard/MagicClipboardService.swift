import AppKit
import SwiftUI
import OSLog

/// Un ítem del historial de portapapeles.
struct ClipboardItem: Identifiable {
    let id = UUID()
    enum Kind {
        case text(String)
        case image(NSImage)
    }
    let kind: Kind
    let sourceAppName: String?
    let sourceIcon: NSImage?
    let date: Date

    var isImage: Bool { if case .image = kind { return true }; return false }

    /// Texto plano del ítem (vacío para imágenes).
    var text: String? {
        if case .text(let s) = kind { return s }
        return nil
    }

    /// Preview de una línea para la lista.
    var preview: String {
        switch kind {
        case .image: return "Image"
        case .text(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            return t.count > 90 ? String(t.prefix(90)) + "…" : t
        }
    }
}

/// **Magic Clipboard** — historial de portapapeles con panel tipo Spotlight.
///
/// Monitorea `NSPasteboard.general` (texto + imágenes), guarda el origen (app)
/// de cada copia y, con una hotkey, abre un panel limpio para buscar y re-pegar
/// lo copiado. Reusa la infra de paste de Magic Selection (CursorPaster).
@MainActor
final class MagicClipboardService: ObservableObject {
    static let shared = MagicClipboardService()

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicClipboardService"
    )

    // ── Preferencias ────────────────────────────────────────────────────
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "magicClipboard.enabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "magicClipboard.enabled")
            if newValue { startMonitoring() } else { stopMonitoring() }
        }
    }
    /// ¿Capturar imágenes además de texto? (default sí.)
    var includeImages: Bool {
        get { UserDefaults.standard.object(forKey: "magicClipboard.includeImages") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "magicClipboard.includeImages") }
    }

    // ── Estado ──────────────────────────────────────────────────────────
    @Published private(set) var history: [ClipboardItem] = []
    private let maxItems = 80

    private var pollTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    /// changeCount de nuestras PROPIAS escrituras (al re-pegar), para no
    /// re-capturarlas como si fueran una copia del usuario.
    private var internalChangeCount: Int = -1

    private let panel = MagicClipboardPanel()
    /// App al frente ANTES de abrir el panel (para re-pegar ahí).
    private var targetAppPID: pid_t?

    private init() {}

    /// Llamar al boot. Arranca el monitor si la feature está activada.
    func startIfEnabled() {
        if isEnabled { startMonitoring() }
    }

    // ── Monitor del portapapeles ────────────────────────────────────────
    private func startMonitoring() {
        guard pollTimer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPasteboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        Self.logger.info("Magic Clipboard monitor started")
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        // Ignorar nuestras propias escrituras (re-pegado).
        guard current != internalChangeCount else { return }

        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName
        let icon = app?.icon

        // Imagen primero (si está habilitado).
        if includeImages,
           let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           pb.string(forType: .string) == nil {
            addItem(ClipboardItem(kind: .image(image), sourceAppName: appName, sourceIcon: icon, date: Date()))
            return
        }

        if let str = pb.string(forType: .string),
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Evitar duplicado inmediato del mismo texto.
            if history.first?.text == str { return }
            addItem(ClipboardItem(kind: .text(str), sourceAppName: appName, sourceIcon: icon, date: Date()))
        }
    }

    private func addItem(_ item: ClipboardItem) {
        history.insert(item, at: 0)
        if history.count > maxItems { history.removeLast(history.count - maxItems) }
    }

    func clearHistory() { history.removeAll() }

    // ── Panel (hotkey) ──────────────────────────────────────────────────
    func togglePanel() {
        guard isEnabled else {
            Self.logger.info("Magic Clipboard hotkey pero la feature está desactivada")
            return
        }
        if panel.isVisible {
            panel.hide()
        } else {
            // Recordamos la app al frente para re-pegar ahí después.
            targetAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            panel.present(service: self)
        }
    }

    // ── Re-pegar / insertar ─────────────────────────────────────────────
    /// Pega un ítem del historial en la app de origen.
    func paste(_ item: ClipboardItem) {
        panel.hide()
        switch item.kind {
        case .text(let s):
            CursorPaster.pasteReactivating(s, appPID: targetAppPID, force: true)
        case .image(let image):
            pasteImage(image)
        }
    }

    /// Inserta un emoji (o cualquier string) en la app de origen.
    func insertText(_ string: String) {
        panel.hide()
        CursorPaster.pasteReactivating(string, appPID: targetAppPID, force: true)
    }

    private func pasteImage(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        internalChangeCount = pb.changeCount
        // Reactivar la app de origen y simular ⌘V.
        if let pid = targetAppPID, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Self.simulatePasteShortcut()
        }
    }

    /// Simula ⌘V (para imágenes; el texto usa CursorPaster).
    private static func simulatePasteShortcut() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
