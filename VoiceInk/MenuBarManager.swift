import SwiftUI
import SwiftData
import AppKit
import OSLog

class MenuBarManager: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MenuBarManager")
    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            updateAppActivationPolicy()
        }
    }

    private var modelContainer: ModelContainer?
    private var engine: VoiceInkEngine?

    init() {
        self.isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
        updateAppActivationPolicy()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard isMenuBarOnly else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let hasVisibleWindows = NSApplication.shared.windows.contains {
                $0.isVisible && $0.level == .normal && !$0.styleMask.contains(.nonactivatingPanel)
            }
            if !hasVisibleWindows && NSApplication.shared.activationPolicy() != .accessory {
                self?.logger.notice("windowDidClose: no visible windows, switching to .accessory policy")
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    func configure(modelContainer: ModelContainer, engine: VoiceInkEngine) {
        self.modelContainer = modelContainer
        self.engine = engine
    }
    
    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }
    
    func applyActivationPolicy() {
        updateAppActivationPolicy()
    }
    
    func focusMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("focusMainWindow: activation policy set to .regular")
        if WindowManager.shared.showMainWindow() == nil {
            logger.error("focusMainWindow: showMainWindow returned nil")
        }
    }
    
    private func updateAppActivationPolicy() {
        let applyPolicy = { [weak self] in
            guard let self else { return }
            let application = NSApplication.shared
            if self.isMenuBarOnly {
                self.logger.notice("updateAppActivationPolicy: switching to .accessory (dock icon hidden)")
                application.setActivationPolicy(.accessory)
                WindowManager.shared.hideMainWindow()
            } else {
                self.logger.notice("updateAppActivationPolicy: switching to .regular (dock icon visible)")
                application.setActivationPolicy(.regular)
                WindowManager.shared.showMainWindow()
            }
        }

        if Thread.isMainThread {
            applyPolicy()
        } else {
            DispatchQueue.main.async(execute: applyPolicy)
        }
    }
    
    func openMainWindowAndNavigate(to destination: String) {
        logger.notice("openMainWindowAndNavigate: requested destination=\(destination, privacy: .public), isMenuBarOnly=\(self.isMenuBarOnly, privacy: .public)")

        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("openMainWindowAndNavigate: activation policy set to .regular")

        if WindowManager.shared.showMainWindow() == nil {
            // Caso: no hay main window ni onboarding window (ambas cerradas).
            // Forzar a AppKit que recree la ventana del WindowGroup activando
            // la app + delegando a applicationShouldHandleReopen.
            logger.notice("openMainWindowAndNavigate: no window to show, requesting AppKit reopen")
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let delegate = NSApplication.shared.delegate {
                _ = delegate.applicationShouldHandleReopen?(NSApplication.shared, hasVisibleWindows: false)
            }

            // Retry una vez después del reopen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if WindowManager.shared.showMainWindow() == nil {
                    self?.logger.error("openMainWindowAndNavigate: still no window after reopen attempt — aborting navigation to \(destination, privacy: .public)")
                    return
                }
                self?.postNavigation(to: destination)
            }
            return
        }

        logger.notice("openMainWindowAndNavigate: window shown, posting navigation notification for \(destination, privacy: .public)")
        postNavigation(to: destination)
    }

    private func postNavigation(to destination: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: ["destination": destination]
            )
            self?.logger.notice("postNavigation: notification posted for \(destination, privacy: .public)")
        }
    }

    func openHistoryWindow() {
        guard let modelContainer = modelContainer,
              let engine = engine else {
            logger.error("openHistoryWindow: dependencies not configured (modelContainer=\(self.modelContainer != nil, privacy: .public), engine=\(self.engine != nil, privacy: .public))")
            return
        }
        logger.notice("openHistoryWindow: opening history window")
        NSApplication.shared.setActivationPolicy(.regular)
        logger.notice("openHistoryWindow: activation policy set to .regular")
        HistoryWindowController.shared.showHistoryWindow(
            modelContainer: modelContainer,
            engine: engine
        )
    }
}
