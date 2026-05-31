import SwiftUI
import Cocoa
import Carbon.HIToolbox
import LaunchAtLogin
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage(PasteMethod.userDefaultsKey) private var pasteMethodRawValue = PasteMethod.standard.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var showResetOnboardingAlert = false
    @State private var hasCancelRecordingShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelRecordingShortcutRecorderResetID = 0

    private func t(_ key: String) -> String {
        AppText.t(key, language: appLanguage)
    }

    // Expansion states - all collapsed by default
    @State private var isMiddleClickExpanded = false
    @State private var isSoundFeedbackExpanded = false
    @State private var isMuteSystemExpanded = false
    @State private var isRestoreClipboardExpanded = false

    // (Las @AppStorage de expansión del acordeón se removieron porque el
    // patrón ahora es Form simple con todas las secciones visibles y
    // scrolleables, estilo Settings clásico de macOS.)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexoSpacing.lg) {
                NexoHero(
                    title: "Settings",
                    subtitle: "Configure shortcuts, recording, language and more.",
                    systemImage: "gearshape.fill"
                )

                // MARK: - Entrada de audio (atajo a vista completa)
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Audio Input", systemImage: "mic.fill",
                                          subtitle: "The microphone used to record your dictation.")
                        Divider()

                        LabeledContent(t("Current Device")) {
                            Text(deviceManager.getDeviceName(deviceID: deviceManager.getCurrentDevice()) ?? AppText.t("System Default", language: appLanguage))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Spacer()
                            Button(t("Open Audio Input settings")) {
                                NotificationCenter.default.post(
                                    name: .navigateToDestination,
                                    object: nil,
                                    userInfo: ["destination": "Audio Input"]
                                )
                            }
                        }
                    }
                }

                // MARK: - Permisos (atajo a vista completa)
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Permissions", systemImage: "shield.lefthalf.filled",
                                          subtitle: "Grant microphone and accessibility access so recording and pasting work.")
                        Divider()

                        HStack {
                            Spacer()
                            Button(t("Open Permissions")) {
                                NotificationCenter.default.post(
                                    name: .navigateToDestination,
                                    object: nil,
                                    userInfo: ["destination": "Permissions"]
                                )
                            }
                        }
                    }
                }

                // MARK: - Idioma
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Language", systemImage: "globe",
                                          subtitle: "The language used for the app interface.")
                        Divider()

                        Picker(t("App Language"), selection: $appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: appLanguage) { _, newValue in
                            if let language = AppLanguage(rawValue: newValue) {
                                LocalizationManager.shared.setLanguage(language)
                            }
                        }
                    }
                }

                // MARK: - Shortcuts
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Shortcuts", systemImage: "keyboard",
                                          subtitle: "The keys you press to start and stop recording.")
                        Divider()

                        LabeledContent(t("Primary Shortcut")) {
                            HStack(spacing: 8) {
                                Spacer()
                                shortcutModePicker(binding: $recordingShortcutManager.primaryRecordingShortcutMode)
                                ShortcutRecorder(action: .primaryRecording) {
                                    recordingShortcutManager.primaryRecordingShortcut = .custom
                                    recordingShortcutManager.updateShortcutStatus()
                                }
                                .controlSize(.small)
                            }
                        }

                        if recordingShortcutManager.secondaryRecordingShortcut != .none {
                            LabeledContent(t("Secondary Shortcut")) {
                                HStack(spacing: 8) {
                                    Spacer()
                                    shortcutModePicker(binding: $recordingShortcutManager.secondaryRecordingShortcutMode)
                                    ShortcutRecorder(action: .secondaryRecording) {
                                        recordingShortcutManager.secondaryRecordingShortcut = .custom
                                        recordingShortcutManager.updateShortcutStatus()
                                    }
                                    .controlSize(.small)
                                    Button {
                                        withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .none }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if recordingShortcutManager.secondaryRecordingShortcut == .none {
                            Button(t("Add Second Shortcut")) {
                                withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .custom }
                            }
                        }
                    }
                }

                // MARK: - Additional Shortcuts
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Additional Shortcuts", systemImage: "command",
                                          subtitle: "Extra keys to paste, retry or cancel a transcription.")
                        Divider()

                        LabeledContent(t("Paste Last Transcription (Original)")) {
                            ShortcutRecorder(action: .pasteLastTranscription) {
                                recordingShortcutManager.updateShortcutStatus()
                            }
                                .controlSize(.small)
                        }

                        LabeledContent(t("Paste Last Transcription (Enhanced)")) {
                            ShortcutRecorder(action: .pasteLastEnhancement) {
                                recordingShortcutManager.updateShortcutStatus()
                            }
                                .controlSize(.small)
                        }

                        LabeledContent(t("Retry Last Transcription")) {
                            ShortcutRecorder(action: .retryLastTranscription) {
                                recordingShortcutManager.updateShortcutStatus()
                            }
                                .controlSize(.small)
                        }

                        LabeledContent(t("Cancel Recording")) {
                            HStack(spacing: 8) {
                                ShortcutRecorder(
                                    action: .cancelRecorder,
                                    defaultShortcut: Self.defaultCancelRecordingShortcut
                                ) {
                                    hasCancelRecordingShortcut = true
                                }
                                    .id(cancelRecordingShortcutRecorderResetID)
                                    .controlSize(.small)

                                Button {
                                    ShortcutStore.setShortcut(nil, for: .cancelRecorder)
                                    hasCancelRecordingShortcut = false
                                    cancelRecordingShortcutRecorderResetID += 1
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.plain)
                                .help(t("Reset to default"))
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
                            guard let action = notification.object as? ShortcutAction, action == .cancelRecorder else { return }
                            hasCancelRecordingShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
                        }

                        // Middle-Click
                        ExpandableSettingsRow(
                            isExpanded: $isMiddleClickExpanded,
                            isEnabled: $recordingShortcutManager.isMiddleClickToggleEnabled,
                            label: "Middle-Click Recording"
                        ) {
                            LabeledContent(t("Activation Delay")) {
                                HStack {
                                    TextField("", value: $recordingShortcutManager.middleClickActivationDelay, formatter: {
                                        let formatter = NumberFormatter()
                                        formatter.minimum = 0
                                        return formatter
                                    }())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                    Text("ms")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // MARK: - Recording Feedback
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Recording Feedback", systemImage: "speaker.wave.2.fill",
                                          subtitle: "Sounds, audio muting and how transcriptions are pasted.")
                        Divider()

                        // Sound Feedback
                        ExpandableSettingsRow(
                            isExpanded: $isSoundFeedbackExpanded,
                            isEnabled: $soundManager.isEnabled,
                            label: "Sound Feedback"
                        ) {
                            CustomSoundSettingsView()
                        }

                        // Mute System Audio
                        ExpandableSettingsRow(
                            isExpanded: $isMuteSystemExpanded,
                            isEnabled: $mediaController.isSystemMuteEnabled,
                            label: "Mute Audio While Recording"
                        ) {
                            Picker(t("Resume Delay"), selection: $mediaController.audioResumptionDelay) {
                                Text("0s").tag(0.0)
                                Text("1s").tag(1.0)
                                Text("2s").tag(2.0)
                                Text("3s").tag(3.0)
                                Text("4s").tag(4.0)
                                Text("5s").tag(5.0)
                            }
                        }

                        // Keep Clipboard Content
                        ExpandableSettingsRow(
                            isExpanded: $isRestoreClipboardExpanded,
                            isEnabled: $restoreClipboardAfterPaste,
                            label: "Keep Clipboard Content",
                            infoMessage: t("Nexo Whisper temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay. When disabled, the pasted transcription stays on your clipboard.")
                        ) {
                            Picker(t("Restore Delay"), selection: $clipboardRestoreDelay) {
                                Text("250ms").tag(0.25)
                                Text("500ms").tag(0.5)
                                Text("1s").tag(1.0)
                                Text("2s").tag(2.0)
                                Text("3s").tag(3.0)
                                Text("4s").tag(4.0)
                                Text("5s").tag(5.0)
                            }
                        }

                        // Paste Method
                        Picker(selection: $pasteMethodRawValue) {
                            ForEach(PasteMethod.allCases) { method in
                                Text(method.displayName).tag(method.rawValue)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(t("Paste Method"))
                                InfoTip("Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly.")
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: pasteMethodRawValue) { _, newValue in
                            guard let method = PasteMethod(rawValue: newValue) else {
                                pasteMethodRawValue = PasteMethod.standard.rawValue
                                return
                            }
                            PasteMethod.setCurrent(method)
                        }
                    }
                }

                // MARK: - Power Mode
                PowerModeSection()

                // MARK: - Interface
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Interface", systemImage: "rectangle.on.rectangle",
                                          subtitle: "The look of the recording indicator that appears while you dictate.")
                        Divider()

                        Picker(t("Recorder Style"), selection: $recorderUIManager.recorderType) {
                            Text("Notch").tag("notch")
                            Text("Mini").tag("mini")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // MARK: - Experimental
                ExperimentalSection()

                // MARK: - Magic Selection (PREVIEW)
                // MagicSelectionSection trae su propio header ("Magic Aura" +
                // PREVIEW), por eso va directo en la NexoCard sin doble header.
                NexoCard {
                    MagicSelectionSection()
                }

                // MARK: - General
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("General", systemImage: "gearshape.fill",
                                          subtitle: "App-wide options like the Dock icon, launch at login and updates.")
                        Divider()

                        Toggle(t("Hide Dock Icon"), isOn: $menuBarManager.isMenuBarOnly)

                        LaunchAtLogin.Toggle("Launch at Login")

                        Toggle(t("Auto-check Updates"), isOn: Binding(
                            get: { updaterViewModel.automaticallyChecksForUpdates },
                            set: { updaterViewModel.setAutomaticallyChecksForUpdates($0) }
                        ))

                        HStack {
                            Button(t("Check for Updates")) {
                                updaterViewModel.checkForUpdates()
                            }
                            .disabled(!updaterViewModel.canCheckForUpdates)

                            Button(t("Reset Onboarding")) {
                                showResetOnboardingAlert = true
                            }
                        }
                    }
                }

                // MARK: - Privacy
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Privacy", systemImage: "lock.fill",
                                          subtitle: "Control how your transcription history and audio recordings are kept or auto-deleted.")
                        Divider()

                        AudioCleanupSettingsView()
                    }
                }

                // MARK: - Backup
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Backup", systemImage: "arrow.down.doc.fill",
                                          subtitle: "Export your settings to a file, or import them from a backup.")
                        Divider()

                        LabeledContent(t("Export Settings")) {
                            Button(t("Export")) {
                                ImportExportService.shared.exportSettings(
                                    enhancementService: enhancementService,
                                    recordingShortcutManager: recordingShortcutManager,
                                    menuBarManager: menuBarManager,
                                    mediaController: mediaController,
                                    playbackController: playbackController,
                                    soundManager: soundManager,
                                    recorderUIManager: recorderUIManager,
                                    modelContext: modelContext
                                )
                            }
                        }

                        LabeledContent(t("Import Settings")) {
                            Button(t("Import")) {
                                ImportExportService.shared.importSettings(
                                    enhancementService: enhancementService,
                                    recordingShortcutManager: recordingShortcutManager,
                                    menuBarManager: menuBarManager,
                                    mediaController: mediaController,
                                    playbackController: playbackController,
                                    soundManager: soundManager,
                                    recorderUIManager: recorderUIManager,
                                    modelContext: modelContext,
                                    transcriptionModelManager: transcriptionModelManager
                                )
                            }
                        }
                        Text(t("Export all settings, or choose specific categories when importing a backup."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Diagnostics
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("Diagnostics", systemImage: "wrench.and.screwdriver.fill",
                                          subtitle: "Export app logs to help troubleshoot a problem.")
                        Divider()

                        DiagnosticsSettingsView()
                    }
                }

                // MARK: - License
                NexoCard {
                    VStack(alignment: .leading, spacing: NexoSpacing.md) {
                        NexoSectionHeader("License", systemImage: "checkmark.seal.fill",
                                          subtitle: "Your plan and activation status.")
                        Divider()

                        LicenseSettingsSection()
                    }
                }
            }
            .nexoPage(maxWidth: 720)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .alert(t("Reset Onboarding"), isPresented: $showResetOnboardingAlert) {
            Button(t("Cancel"), role: .cancel) { }
            Button(t("Reset"), role: .destructive) {
                DispatchQueue.main.async {
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text(t("You'll see the introduction screens again the next time you launch the app."))
        }
    }

    private static let defaultCancelRecordingShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    @ViewBuilder
    private func shortcutModePicker(binding: Binding<RecordingShortcutManager.Mode>) -> some View {
        Picker("", selection: binding) {
            ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - Expandable Settings Row (entire row clickable)

struct ExpandableSettingsRow<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool
    let label: LocalizedStringKey
    var infoMessage: String? = nil
    var infoURL: String? = nil
    @ViewBuilder let content: () -> Content

    @State private var isHandlingToggleChange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row - entire area is tappable
            HStack {
                Toggle(isOn: $isEnabled) {
                    HStack(spacing: 4) {
                        Text(label)
                        if let message = infoMessage {
                            if let url = infoURL {
                                InfoTip(resolved: message, learnMoreURL: url)
                            } else {
                                InfoTip(resolved: message)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isEnabled && isExpanded ? 90 : 0))
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHandlingToggleChange else { return }
                if isEnabled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Expanded content with proper spacing
            if isEnabled && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 12)
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: isEnabled) { _, newValue in
            isHandlingToggleChange = true
            if newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isHandlingToggleChange = false
            }
        }
    }
}

// MARK: - Power Mode Section

struct PowerModeSection: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @AppStorage("powerModePersistConfig") private var powerModePersistSettings = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var showDisableAlert = false
    @State private var isExpanded = false

    private func t(_ key: String) -> String {
        AppText.t(key, language: appLanguage)
    }

    var body: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Power Mode", systemImage: "bolt.fill",
                                  subtitle: "Apply different preferences automatically depending on the active app or website.")
                Divider()

                ExpandableSettingsRow(
                    isExpanded: $isExpanded,
                    isEnabled: toggleBinding,
                    label: "Power Mode",
                    infoMessage: t("Apply custom settings based on active app or website."),
                    infoURL: NexoURLs.docsAppProfiles
                ) {
                    Toggle(isOn: $powerModePersistSettings) {
                        HStack(spacing: 4) {
                            Text(t("Persist Configured Preferences"))
                            InfoTip("When enabled, Power Mode preferences stay active after you stop recording instead of reverting to your original preferences. They will only change when a different Power Mode activates.")
                        }
                    }
                }
            }
        }
        .alert(t("Power Mode Still Active"), isPresented: $showDisableAlert) {
            Button(t("Got it"), role: .cancel) { }
        } message: {
            Text(t("Disable or remove your Power Modes first."))
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { powerModeUIFlag },
            set: { newValue in
                if newValue {
                    powerModeUIFlag = true
                    NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
                } else if powerModeManager.configurations.allSatisfy({ !$0.isEnabled }) {
                    powerModeUIFlag = false
                    NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
                } else {
                    showDisableAlert = true
                }
            }
        )
    }
}

// MARK: - Experimental Section

struct ExperimentalSection: View {
    @ObservedObject private var playbackController = PlaybackController.shared
    @ObservedObject private var mediaController = MediaController.shared
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var isPauseMediaExpanded = false

    private func t(_ key: String) -> String {
        AppText.t(key, language: appLanguage)
    }

    var body: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Experimental", systemImage: "flask.fill",
                                  subtitle: "Newer options that are still being tested.")
                Divider()

                ExpandableSettingsRow(
                    isExpanded: $isPauseMediaExpanded,
                    isEnabled: $playbackController.isPauseMediaEnabled,
                    label: "Pause Media While Recording",
                    infoMessage: t("Pauses playing media when recording starts and resumes when done.")
                ) {
                    Picker(t("Resume Delay"), selection: $mediaController.audioResumptionDelay) {
                        Text("0s").tag(0.0)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("4s").tag(4.0)
                        Text("5s").tag(5.0)
                    }
                }
            }
        }
    }
}

// MARK: - Text Extension

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
