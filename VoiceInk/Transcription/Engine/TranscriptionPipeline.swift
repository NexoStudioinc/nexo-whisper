import Foundation
import SwiftData
import os

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → start paste + dismiss → save
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let promptDetectionService = PromptDetectionService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionPipeline")

    var licenseViewModel: LicenseViewModel

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry,
        enhancementService: AIEnhancementService?
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
        self.enhancementService = enhancementService
        // Singleton: el viewmodel es global y reactivo. Asignarlo desde el
        // exterior tras un cambio de status (como hacía VoiceInkEngine) ya
        // no es necesario — el singleton se auto-actualiza.
        self.licenseViewModel = LicenseViewModel.shared
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - audioURL: The recorded audio file.
    ///   - model: The transcription model to use.
    ///   - session: An active streaming session if one was prepared, otherwise nil.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCancel: Called when cancellation is detected to cancel active session state.
    ///   - onDismiss: Called as soon as paste is initiated to dismiss the recorder panel.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (RecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        var finalPastedText: String?
        var promptDetectionResult: PromptDetectionService.PromptDetectionResult?
        var didInsertSessionMetric = false

        func restorePromptDetectionSettingsIfNeeded() async {
            if let result = promptDetectionResult,
               let enhancementService,
               result.shouldEnableAI {
                await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
            }
        }

        func restorePromptDetectionSettingsAndDismiss(afterRestore: () -> Void = {}) async {
            await restorePromptDetectionSettingsIfNeeded()
            afterRestore()
            await onDismiss()
        }

        func finishCanceledTranscription() async {
            await onCancel()
            await restorePromptDetectionSettingsIfNeeded()

            let canceledDuration: TimeInterval?
            if transcription.duration > 0 {
                canceledDuration = nil
            } else {
                let duration = await AudioFileMetadata.duration(for: audioURL)
                canceledDuration = duration > 0 ? duration : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? model.displayName
            )

            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save canceled transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        do {
            let transcriptionStart = Date()
            var text: String
            if let session {
                text = try await session.transcribe(audioURL: audioURL)
            } else {
                text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            text = TranscriptionOutputFilter.filter(text)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            if shouldCancel() { await finishCanceledTranscription(); return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                text = WhisperTextFormatter.format(text)
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            let cleanedText = TranscriptionOutputFilter.applyUserCleanupPreferences(text)

            let actualDuration = await AudioFileMetadata.duration(for: audioURL)

            transcription.text = cleanedText
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            finalPastedText = cleanedText

            if let enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }

            let isSkipShortEnhancementEnabled = UserDefaults.standard.bool(forKey: "SkipShortEnhancement")
            let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
            let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
            let shouldSkipEnhancement = isSkipShortEnhancementEnabled && WordCounter.count(in: text) <= shortEnhancementWordThreshold && !(promptDetectionResult?.shouldEnableAI == true)

            if let enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured,
               !shouldSkipEnhancement {
                if shouldCancel() { await finishCanceledTranscription(); return }

                onStateChange(.enhancing)
                let textForAI = promptDetectionResult?.processedText ?? text

                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    finalPastedText = enhancedText
                } catch {
                    // Falla del enhancement: NO sobrescribir transcription.enhancedText
                    // con el mensaje de error (eso ensucia el historial y se ve raro
                    // al re-pegar). Dejamos enhancedText en nil — finalPastedText ya
                    // tiene cleanedText (la transcripción cruda) asignado más arriba,
                    // así que el usuario igual recibe su texto pegado.
                    let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    // Mostramos hasta 200 chars del error real (no 80) para que el
                    // usuario vea por qué falló sin truncar info útil.
                    let reason = String(errorDescription.prefix(200))
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: String(localized: "AI enhancement failed — pasted raw transcription") + " — \(reason)",
                            type: .warning,
                            duration: 8.0
                        )
                    }
                    if shouldCancel() { await finishCanceledTranscription(); return }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

            if let nativeAppleError = error as? NativeAppleTranscriptionService.ServiceError,
               case .assetDownloadRequired = nativeAppleError {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: errorDescription,
                        type: .error,
                        duration: 5.0
                    )
                }
            }

            transcription.text = "Transcription Failed: \(errorDescription)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        func saveTranscriptionAndPostCompletion() {
            if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                do {
                    didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                        transcription: transcription,
                        model: model,
                        in: modelContext
                    )
                } catch {
                    logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
                }
            }

            do {
                try modelContext.save()
                if didInsertSessionMetric {
                    NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
                }
                NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)

                // Alimentamos el tracker de palabras raras para que pueda
                // sugerir agregar términos al diccionario después de N apariciones.
                // Defensivo: snapshot del texto antes del dispatch, tracking
                // nunca debe romper la transcripción.
                if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                    let textForTracker = transcription.text
                    let ctx = modelContext
                    Task { @MainActor in
                        do {
                            RareWordTracker.shared.feed(text: textForTracker, modelContext: ctx)
                        }
                    }
                }
            } catch {
                logger.error("Failed to save transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        if let textToPaste = finalPastedText,
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            // Tras la migración a freemium (sin trial), la transcripción local
            // es libre — no se inyecta más banner "trial expired" en el paste.
            // El gating de features Pro vive en FeatureGate, no en esta capa.

            let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
            let pastedText = textToPaste + (appendSpace ? " " : "")
            let pasteResult = await CursorPaster.startPasteAtCursor(pastedText).value

            // SAFETY NET CRÍTICA: el texto SIEMPRE termina en el clipboard como
            // red de seguridad. Si la mejora IA tardó y el usuario perdió foco,
            // o si el paste no llegó al lugar correcto, puede recuperarlo con
            // Cmd+V manual. Esto corre DESPUÉS del clipboard restore (que se
            // ejecuta dentro de CursorPaster con un delay), para que nuestra
            // escritura tenga la última palabra y no se pierda la transcripción.
            let safetyNetText = pastedText
            Task { @MainActor in
                let restoreDelay = max(
                    UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
                    0.25
                )
                // Esperamos restoreDelay + buffer para asegurarnos de quedar
                // últimos en escribir al pasteboard.
                let waitSeconds = restoreDelay + 0.5
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                _ = ClipboardManager.setClipboard(safetyNetText, transient: false, sessionID: nil)
            }

            // Fallback: si no había text field para recibir el paste, avisamos
            // al usuario que el texto quedó en el clipboard.
            if pasteResult == .noTextFieldFocused {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: String(localized: "No place to paste — transcription copied to clipboard"),
                        type: .info,
                        duration: 6.0
                    )
                }
            }

            let autoSendKey = PowerModeManager.shared.currentActiveConfiguration?.autoSendKey
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss {
                if let autoSendKey, autoSendKey.isEnabled, pasteResult == .commandPosted {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
        } else {
            await restorePromptDetectionSettingsAndDismiss()
        }

        saveTranscriptionAndPostCompletion()
    }
}
