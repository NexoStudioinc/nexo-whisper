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
        // minSize bajado de 900x780 -> 720x520 para que entre cómodo en MacBook
        // Air 11" (1366x768) y similares. El layout SwiftUI ya usa GeometryReader
        // y se adapta. El tamaño "ideal" se calcula en applyOnboardingInitialPlacement
        // según la pantalla activa.
        window.minSize = NSSize(width: 720, height: 520)
        applyOnboardingInitialPlacement(to: window)
        window.makeKeyAndOrderFront(nil)
    }

    private func applyOnboardingInitialPlacement(to window: NSWindow) {
        // Open onboarding on the screen the user is currently looking at,
        // mirroring how the main window behaves. `NSScreen.main` returns the
        // screen with the active app's focus; if unavailable, fall back to the
        // screen containing the cursor, then to the first attached display.
        let activeScreen = NSScreen.main
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.screens.first
        guard let screen = activeScreen else { return }

        let visibleFrame = screen.visibleFrame

        // Ideal size para pantallas grandes, pero nunca más grande que la
        // pantalla disponible menos un margin razonable. Esto evita que en
        // displays chicos (MacBook Air 11"/13") los botones queden cortados.
        let preferredSize = NSSize(width: 900, height: 780)
        let margin: CGFloat = 32
        let targetSize = NSSize(
            width: min(preferredSize.width, visibleFrame.width - margin),
            height: min(preferredSize.height, visibleFrame.height - margin)
        )

        let origin = NSPoint(
            x: visibleFrame.midX - targetSize.width / 2,
            y: visibleFrame.midY - targetSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: targetSize), display: false)
        fitWindowToVisibleScreen(window)
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
    }
    
    func showMainWindow() -> NSWindow? {
        guard let window = resolveMainWindow() else {
            return nil
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return window
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
