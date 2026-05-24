import SwiftUI
import AppKit
import OSLog

class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.mainWindow")
    private static let onboardingWindowIdentifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.onboardingWindow")
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName("VoiceInkMainWindowFrame")

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WindowManager")
    private weak var mainWindow: NSWindow?
    // Mantener referencia al onboarding mientras esté en uso, para que el
    // menubar pueda traerlo al frente si el usuario lo cerró sin terminar.
    private weak var onboardingWindow: NSWindow?
    private var didApplyInitialPlacement = false

    private override init() {
        super.init()
    }
    
    func configureWindow(_ window: NSWindow) {
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier && $0 != window }) {
            logger.notice("configureWindow: duplicate detected, reusing existing window")
            window.close()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        logger.notice("configureWindow: registering main window")
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.title = "Nexo Whisper"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 760, height: 560)
        window.setFrameAutosaveName(Self.mainWindowAutosaveName)
        applyInitialPlacementIfNeeded(to: window)
        registerMainWindowIfNeeded(window)
        window.orderFrontRegardless()
    }
    
    func configureOnboardingPanel(_ window: NSWindow) {
        if window.identifier == nil || window.identifier != Self.onboardingWindowIdentifier {
            window.identifier = Self.onboardingWindowIdentifier
        }
        // Trackear la ventana para poder traerla al frente desde el menubar
        // si el usuario la cerró sin completar el onboarding.
        onboardingWindow = window
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "Nexo Whisper Onboarding"
        window.isOpaque = false
        // El tamaño del wizard lo controla SwiftUI desde el Scene del WindowGroup
        // (.defaultSize 900x640 + .frame minWidth/minHeight 760x560 + .windowResizability(.contentSize)).
        // Acá solo nos encargamos de POSICIONAR la ventana en la pantalla activa
        // y CLAMPEAR al visibleFrame si la pantalla es chica. Tocar minSize/setFrame
        // tamaño directo entra en conflicto con windowResizability(.contentSize)
        // y la pisa SwiftUI inmediatamente.
        centerOnActiveScreen(window)
        fitWindowToVisibleScreen(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        // Resolver la pantalla con foco actual (donde está el cursor / la barra
        // de menú activa). Fallback a la pantalla que contiene el cursor, después
        // a la primera disponible.
        let activeScreen = NSScreen.main
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.screens.first
        guard let screen = activeScreen else { return }

        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
        window.setFrameOrigin(origin)
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
    }
    
    func showMainWindow() -> NSWindow? {
        // Si el main window no existe (típico cuando el usuario está en
        // onboarding y no lo completó), fallback al onboarding window.
        // Sin esto, el menubar item "Configuración" no abre nada cuando
        // el wizard no terminó.
        let target = resolveMainWindow() ?? resolveOnboardingWindow()
        guard let window = target else {
            return nil
        }

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return window
    }

    private func resolveOnboardingWindow() -> NSWindow? {
        if let window = onboardingWindow {
            return window
        }
        // Fallback: buscar por identifier en NSApp.windows en caso de que
        // la referencia weak se haya perdido pero la ventana siga viva.
        return NSApplication.shared.windows.first { $0.identifier == Self.onboardingWindowIdentifier }
    }
    
    func hideMainWindow() {
        guard let window = resolveMainWindow() else {
            return
        }
        window.orderOut(nil)
    }
    
    func currentMainWindow() -> NSWindow? {
        resolveMainWindow()
    }
    
    private func registerMainWindowIfNeeded(_ window: NSWindow) {
        // Only register the primary content window, identified by the hidden title bar style
        if window.identifier == nil || window.identifier != Self.mainWindowIdentifier {
            registerMainWindow(window)
        }
    }
    
    private func applyInitialPlacementIfNeeded(to window: NSWindow) {
        guard !didApplyInitialPlacement else { return }
        // Attempt to restore previous frame if one exists; otherwise fall back to a centered placement
        if !window.setFrameUsingName(Self.mainWindowAutosaveName) {
            window.center()
        }
        fitWindowToVisibleScreen(window)
        didApplyInitialPlacement = true
    }

    private func fitWindowToVisibleScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        var frame = window.frame

        frame.size.width = min(max(frame.width, window.minSize.width), visibleFrame.width)
        frame.size.height = min(max(frame.height, window.minSize.height), visibleFrame.height)

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        window.setFrame(frame, display: true)
    }
    
    private func resolveMainWindow() -> NSWindow? {
        if let window = mainWindow {
            return window
        }

        logger.notice("resolveMainWindow: weak ref is nil, searching \(NSApplication.shared.windows.count, privacy: .public) windows by identifier")

        if let window = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier }) {
            logger.notice("resolveMainWindow: recovered window via identifier fallback")
            mainWindow = window
            window.delegate = self
            return window
        }

        let windowIDs = NSApplication.shared.windows.map { $0.identifier?.rawValue ?? "nil" }.joined(separator: ", ")
        logger.error("resolveMainWindow: FAILED — no window found with main identifier. Total windows: \(NSApplication.shared.windows.count, privacy: .public), identifiers: \(windowIDs, privacy: .public)")
        return nil
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.identifier == Self.mainWindowIdentifier {
            logger.notice("windowWillClose: main window closing, clearing weak reference")
            window.orderOut(nil)
            mainWindow = nil
            didApplyInitialPlacement = false
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
} 
