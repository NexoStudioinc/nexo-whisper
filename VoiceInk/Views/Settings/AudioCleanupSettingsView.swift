import SwiftUI
import SwiftData

struct AudioCleanupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Audio cleanup settings
    @AppStorage("IsTranscriptionCleanupEnabled") private var isTranscriptionCleanupEnabled = false
    @AppStorage("TranscriptionRetentionMinutes") private var transcriptionRetentionMinutes = 24 * 60
    @AppStorage("IsAudioCleanupEnabled") private var isAudioCleanupEnabled = false
    @AppStorage("AudioRetentionPeriod") private var audioRetentionPeriod = 7
    @State private var isPerformingCleanup = false
    @State private var isShowingConfirmation = false
    @State private var cleanupInfo: (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) = (0, 0, [])
    @State private var showResultAlert = false
    @State private var cleanupResult: (deletedCount: Int, errorCount: Int) = (0, 0)
    @State private var showTranscriptCleanupResult = false
    @State private var transcriptDeletedCount = 0

    // Expansion states - collapsed by default
    @State private var isTranscriptExpanded = false
    @State private var isAudioExpanded = false
    @State private var isHandlingTranscriptToggle = false
    @State private var isHandlingAudioToggle = false

    var body: some View {
        Group {
            // Transcript cleanup - hierarchical
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Toggle(isOn: $isTranscriptionCleanupEnabled) {
                        HStack(spacing: 4) {
                            Text("Auto-delete Transcripts")
                            InfoTip("Automatically delete transcript history based on the retention period you set.")
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isTranscriptionCleanupEnabled && isTranscriptExpanded ? 90 : 0))
                        .opacity(isTranscriptionCleanupEnabled ? 1 : 0.4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isHandlingTranscriptToggle else { return }
                    if isTranscriptionCleanupEnabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTranscriptExpanded.toggle()
                        }
                    }
                }

                if isTranscriptionCleanupEnabled && isTranscriptExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Delete After", selection: $transcriptionRetentionMinutes) {
                            Text("Immediately").tag(0)
                            Text("1 hour").tag(60)
                            Text("1 day").tag(24 * 60)
                            Text("3 days").tag(3 * 24 * 60)
                            Text("7 days").tag(7 * 24 * 60)
                        }

                        Button("Run Cleanup Now") {
                            Task {
                                // El servicio ahora corre en @MainActor con el
                                // modelContext de la vista, así el @Query de
                                // History se entera del borrado y la UI se
                                // refresca inmediatamente.
                                let count = await TranscriptionAutoCleanupService.shared.runManualCleanup(modelContext: modelContext)
                                transcriptDeletedCount = count
                                showTranscriptCleanupResult = true
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isTranscriptExpanded)
            .alert("Transcript Cleanup", isPresented: $showTranscriptCleanupResult) {
                Button("OK", role: .cancel) { }
            } message: {
                if transcriptDeletedCount == 0 {
                    Text("No transcriptions older than the selected retention period were found.")
                } else if transcriptDeletedCount == 1 {
                    Text("Deleted 1 transcription.")
                } else {
                    Text("Deleted \(transcriptDeletedCount) transcriptions.")
                }
            }
            .onChange(of: isTranscriptionCleanupEnabled) { _, newValue in
                isHandlingTranscriptToggle = true
                if newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTranscriptExpanded = true
                    }
                } else {
                    isTranscriptExpanded = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isHandlingTranscriptToggle = false
                }
            }

            Divider().opacity(0.4)

            // Audio cleanup (independiente del borrado de transcripciones: borra
            // solo el archivo de audio y conserva el texto). Siempre visible.
            VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Toggle(isOn: $isAudioCleanupEnabled) {
                            HStack(spacing: 4) {
                                Text("Auto-delete Audio Files")
                                InfoTip("Automatically delete audio recordings while keeping text transcripts intact.")
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isAudioCleanupEnabled && isAudioExpanded ? 90 : 0))
                            .opacity(isAudioCleanupEnabled ? 1 : 0.4)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isHandlingAudioToggle else { return }
                        if isAudioCleanupEnabled {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isAudioExpanded.toggle()
                            }
                        }
                    }

                    if isAudioCleanupEnabled && isAudioExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Keep Audio For", selection: $audioRetentionPeriod) {
                                Text("Immediately").tag(0)
                                Text("1 day").tag(1)
                                Text("3 days").tag(3)
                                Text("7 days").tag(7)
                                Text("14 days").tag(14)
                                Text("30 days").tag(30)
                            }

                            Button(isPerformingCleanup ? "Analyzing..." : "Run Cleanup Now") {
                                Task {
                                    await MainActor.run { isPerformingCleanup = true }
                                    let info = await AudioCleanupManager.shared.getCleanupInfo(modelContext: modelContext)
                                    await MainActor.run {
                                        cleanupInfo = info
                                        isPerformingCleanup = false
                                        isShowingConfirmation = true
                                    }
                                }
                            }
                            .disabled(isPerformingCleanup)
                        }
                        .padding(.top, 12)
                        .padding(.leading, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isAudioExpanded)
                .alert("Audio Cleanup", isPresented: $isShowingConfirmation) {
                    Button("Cancel", role: .cancel) { }

                    if cleanupInfo.fileCount > 0 {
                        Button("Delete \(cleanupInfo.fileCount) Files", role: .destructive) {
                            Task {
                                await MainActor.run { isPerformingCleanup = true }
                                let result = await AudioCleanupManager.shared.runCleanupForTranscriptions(
                                    modelContext: modelContext,
                                    transcriptions: cleanupInfo.transcriptions
                                )
                                await MainActor.run {
                                    cleanupResult = result
                                    isPerformingCleanup = false
                                    showResultAlert = true
                                }
                            }
                        }
                    }
                } message: {
                    if cleanupInfo.fileCount > 0 {
                        Text("This will delete \(cleanupInfo.fileCount) audio files (\(AudioCleanupManager.shared.formatFileSize(cleanupInfo.totalSize))).")
                    } else if audioRetentionPeriod == 0 {
                        Text("No audio files to delete.")
                    } else {
                        Text("No audio files found older than \(audioRetentionPeriod) day\(audioRetentionPeriod > 1 ? "s" : "").")
                    }
                }
                .alert("Cleanup Complete", isPresented: $showResultAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    if cleanupResult.errorCount > 0 {
                        Text("Deleted \(cleanupResult.deletedCount) files. Failed: \(cleanupResult.errorCount).")
                    } else {
                        Text("Deleted \(cleanupResult.deletedCount) audio files.")
                    }
                }
                .onChange(of: isAudioCleanupEnabled) { _, newValue in
                    isHandlingAudioToggle = true
                    if newValue {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAudioExpanded = true
                        }
                        AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
                    } else {
                        isAudioExpanded = false
                        AudioCleanupManager.shared.stopAutomaticCleanup()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isHandlingAudioToggle = false
                    }
                }
        }
    }
}
