import SwiftUI
import AVFoundation
import Cocoa
import IOKit.hid

class PermissionManager: ObservableObject {
    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isScreenRecordingEnabled = false
    @Published var isInputMonitoringEnabled = false
    @Published var isKeyboardShortcutSet = false

    init() {
        // Start observing system events that might indicate permission changes
        setupNotificationObservers()

        // Initial permission checks
        checkAllPermissions()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotificationObservers() {
        // Only observe when app becomes active, as this is a likely time for permissions to have changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidBecomeActive() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
        checkInputMonitoringPermission()
        checkKeyboardShortcut()
    }

    /// Input Monitoring (Listen to keyboard events globally) — necesario
    /// para el hotkey de grabación. Sin este permiso `CGEvent.tapCreate`
    /// no recibe los keystrokes y el atajo no funciona.
    func checkInputMonitoringPermission() {
        // IOHIDCheckAccess no muestra prompt; solo consulta el estado.
        // Valores: .granted, .denied, .unknown (= no preguntado todavía).
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        DispatchQueue.main.async {
            self.isInputMonitoringEnabled = (status == kIOHIDAccessTypeGranted)
        }
    }

    /// Dispara el prompt nativo del sistema. Si el usuario nunca lo
    /// denegó, esto agrega Nexo Whisper a la lista de Input Monitoring.
    /// Si ya está denegado, no hace nada — hay que ir manualmente a
    /// System Settings (el botón se encarga de abrir esa pantalla).
    func requestInputMonitoringPermission() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
    
    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityEnabled = accessibilityEnabled
        }
    }
    
    func checkScreenRecordingPermission() {
        DispatchQueue.main.async {
            self.isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
        }
    }
    
    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }
    
    func checkAudioPermissionStatus() {
        DispatchQueue.main.async {
            self.audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }
    
    func requestAudioPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.audioPermissionStatus = granted ? .authorized : .denied
            }
        }
    }
    
    func checkKeyboardShortcut() {
        DispatchQueue.main.async {
            self.isKeyboardShortcutSet = ShortcutStore.shortcut(for: .primaryRecording) != nil
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let isGranted: Bool
    let buttonTitle: LocalizedStringKey
    // Nota: cuando agregues una instancia de PermissionCard, pasá los strings
    // como literales — SwiftUI los convierte a LocalizedStringKey y se localizan
    // desde Localizable.xcstrings automáticamente.
    let buttonAction: () -> Void
    let checkPermission: () -> Void
    var infoTipMessage: String?
    var infoTipLink: String?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? .green : .orange)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        if let message = infoTipMessage {
                            if let link = infoTipLink, !link.isEmpty {
                                InfoTip(resolved: message, learnMoreURL: link)
                            } else {
                                InfoTip(resolved: message)
                            }
                        }
                    }
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator with refresh
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isRefreshing = true
                        }
                        checkPermission()
                        
                        // Reset the animation after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    
                    if isGranted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .symbolRenderingMode(.hierarchical)
                    } else {
                        Image(systemName: "xmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            
            if !isGranted {
                Button(action: buttonAction) {
                    HStack {
                        Text(buttonTitle)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(NexoSpacing.md)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: NexoRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NexoRadius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct PermissionsView: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexoSpacing.lg) {
                NexoHero(
                    title: "App Permissions",
                    subtitle: "Nexo Whisper needs these macOS permissions to record, paste and detect your shortcut.",
                    systemImage: "shield.lefthalf.filled"
                )

                // Permission Cards agrupadas en una NexoCard con header claro.
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Required Permissions", systemImage: "checklist",
                                          subtitle: "Grant each one in System Settings. Tap refresh after granting to update the status.")
                        Divider()
                    // Keyboard Shortcut Permission
                    //
                    // Importante: leer `isGranted` desde `permissionManager.isKeyboardShortcutSet`
                    // (NO desde `recordingShortcutManager.isShortcutConfigured`).
                    //
                    // El botón de refresh ejecuta `permissionManager.checkKeyboardShortcut()`,
                    // que actualiza `permissionManager.isKeyboardShortcutSet` leyendo el estado
                    // real desde `ShortcutStore`. Si la card mira otra variable (la del
                    // RecordingShortcutManager externo) el refresh no surte efecto visible y
                    // queda colgada en el estado inicial. Las otras 4 cards de esta vista
                    // siguen el mismo patrón (todas leen de permissionManager).
                    PermissionCard(
                        icon: "keyboard",
                        title: "Keyboard Shortcut",
                        description: "Set up a keyboard shortcut to use Nexo Whisper anywhere",
                        isGranted: permissionManager.isKeyboardShortcutSet,
                        buttonTitle: "Configure Shortcut",
                        buttonAction: {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Settings"]
                            )
                        },
                        checkPermission: { permissionManager.checkKeyboardShortcut() }
                    )
                    
                    // Audio Permission
                    PermissionCard(
                        icon: "mic",
                        title: "Microphone Access",
                        description: "Allow Nexo Whisper to record your voice for transcription",
                        isGranted: permissionManager.audioPermissionStatus == .authorized,
                        buttonTitle: permissionManager.audioPermissionStatus == .notDetermined ? "Request Permission" : "Open System Settings",
                        buttonAction: {
                            if permissionManager.audioPermissionStatus == .notDetermined {
                                permissionManager.requestAudioPermission()
                            } else {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        },
                        checkPermission: { permissionManager.checkAudioPermissionStatus() }
                    )
                    
                    // Accessibility Permission
                    PermissionCard(
                        icon: "hand.raised",
                        title: "Accessibility Access",
                        description: "Allow Nexo Whisper to paste transcribed text directly at your cursor position",
                        isGranted: permissionManager.isAccessibilityEnabled,
                        buttonTitle: "Open System Settings",
                        buttonAction: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkAccessibilityPermissions() },
                        infoTipMessage: String(localized: "Nexo Whisper uses Accessibility permissions to paste the transcribed text directly into other applications at your cursor's position. This allows for a seamless dictation experience across your Mac.")
                    )
                    
                    // Input Monitoring Permission — necesario para que el
                    // atajo global de grabación reciba los keystrokes.
                    // Sin este permiso el hotkey no dispara nada, y al
                    // usuario sin documentación le parece que la app está rota.
                    PermissionCard(
                        icon: "keyboard.badge.eye",
                        title: "Input Monitoring Access",
                        description: "Allow Nexo Whisper to detect your global keyboard shortcut",
                        isGranted: permissionManager.isInputMonitoringEnabled,
                        buttonTitle: "Open System Settings",
                        buttonAction: {
                            // Disparamos el prompt nativo (agrega la app a
                            // la lista) y abrimos directo el panel exacto.
                            permissionManager.requestInputMonitoringPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkInputMonitoringPermission() },
                        infoTipMessage: String(localized: "Required for the global recording shortcut to work. Without this permission, pressing your hotkey does nothing.")
                    )

                    // Screen Recording Permission
                    PermissionCard(
                        icon: "rectangle.on.rectangle",
                        title: "Screen Recording Access",
                        description: "Allow Nexo Whisper to understand context from your screen for transcript Enhancement",
                        isGranted: permissionManager.isScreenRecordingEnabled,
                        buttonTitle: "Request Permission",
                        buttonAction: {
                            permissionManager.requestScreenRecordingPermission()
                            // After requesting, open system preferences as fallback
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkScreenRecordingPermission() },
                        infoTipMessage: String(localized: "Nexo Whisper captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored."),
                        infoTipLink: NexoURLs.docsContext
                    )
                    }
                }
            }
            .nexoPage()
        }
        .background(Color(NSColor.underPageBackgroundColor))
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }
}

#Preview {
    PermissionsView()
} 
