import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

enum ModelFilter: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case local = "Local"
    case cloud = "Cloud"
    case custom = "Custom"
    var id: String { self.rawValue }
}

struct ModelManagementView: View {
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var customModelToEdit: CustomCloudModel?
    @StateObject private var aiService = AIService()
    @StateObject private var customModelManager = CustomCloudModelManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @State private var selectedFilter: ModelFilter = .recommended
    @State private var isShowingSettings = false
    @State private var localModelsRootPath = LocalModelStorage.rootDirectory.path

    private let settingsPanelWidth: CGFloat = 400

    // State for the unified alert
    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    private func closeSettings() {
        withAnimation(.smooth(duration: 0.3)) {
            isShowingSettings = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexoSpacing.lg) {
                NexoHero(
                    title: "Transcription Models",
                    subtitle: "Choose the model that turns your voice into text, set its language and manage downloads.",
                    systemImage: "waveform"
                )

                if SystemArchitecture.isIntelMac {
                    intelMacWarningBanner
                }

                defaultModelSection
                languageSelectionSection
                availableModelsSection
            }
            .nexoPage()
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.underPageBackgroundColor))
        .slidingPanel(isPresented: $isShowingSettings, width: settingsPanelWidth) {
            settingsPanelContent
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
    }

    private var settingsPanelContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Model Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { closeSettings() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            ModelSettingsView(whisperPrompt: whisperPrompt)
        }
    }
    
    private var defaultModelSection: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Default Model", systemImage: "checkmark.seal",
                                  subtitle: "The model used for every transcription. Pick it from the list below.")
                Divider()
                Text(transcriptionModelManager.currentTranscriptionModel?.displayName ?? "No model selected")
                    .font(.title2)
                    .fontWeight(.bold)
            }
        }
    }

    private var languageSelectionSection: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Language", systemImage: "globe",
                                  subtitle: "Set the language the model should expect, or let it detect it automatically.")
                Divider()
                LanguageSelectionView(transcriptionModelManager: transcriptionModelManager, displayMode: .full, whisperPrompt: whisperPrompt)
            }
        }
    }
    
    private var availableModelsSection: some View {
        NexoCard {
        VStack(alignment: .leading, spacing: 16) {
            NexoSectionHeader("Available Models", systemImage: "square.stack.3d.up",
                              subtitle: "Browse, download and switch between transcription models. Filter by recommended, local, cloud or custom.")
            Divider()

            HStack {
                // Modern compact pill switcher
                HStack(spacing: 12) {
                    ForEach(ModelFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedFilter = filter
                                isShowingSettings = false
                            }
                        }) {
                            Text(LocalizedStringKey(filter.rawValue))
                                .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                                .foregroundColor(selectedFilter == filter ? .primary : .primary.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    CardBackground(isSelected: selectedFilter == filter, cornerRadius: 22)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingSettings.toggle()
                    }
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isShowingSettings ? .accentColor : .primary.opacity(0.7))
                        .padding(12)
                        .background(
                            CardBackground(isSelected: isShowingSettings, cornerRadius: 22)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 12)
            
            VStack(spacing: 12) {
                    if selectedFilter == .local {
                        localModelStorageSection
                    }

                    ForEach(filteredModels, id: \.id) { model in
                        let isWarming = (model as? WhisperModel).map { whisperModel in
                            warmupCoordinator.isWarming(modelNamed: whisperModel.name)
                        } ?? false

                        ModelCardView(
                            model: model,
                            fluidAudioModelManager: fluidAudioModelManager,
                            transcriptionModelManager: transcriptionModelManager,
                            isDownloaded: whisperModelManager.availableModels.contains { $0.name == model.name },
                            isCurrent: transcriptionModelManager.currentTranscriptionModel?.name == model.name,
                            downloadProgress: whisperModelManager.downloadProgress,
                            modelURL: whisperModelManager.availableModels.first { $0.name == model.name }?.url,
                            isWarming: isWarming,
                            deleteAction: {
                                if let customModel = model as? CustomCloudModel {
                                    alertTitle = "Delete Custom Model"
                                    alertMessage = "Are you sure you want to delete the custom model '\(customModel.displayName)'?"
                                    deleteActionClosure = {
                                        customModelManager.removeCustomModel(withId: customModel.id)
                                        transcriptionModelManager.refreshAllAvailableModels()
                                    }
                                    isShowingDeleteAlert = true
                                } else if let downloadedModel = whisperModelManager.availableModels.first(where: { $0.name == model.name }) {
                                    alertTitle = "Delete Model"
                                    alertMessage = "Are you sure you want to delete the model '\(downloadedModel.name)'?"
                                    deleteActionClosure = {
                                        Task {
                                            await whisperModelManager.deleteModel(downloadedModel)
                                        }
                                    }
                                    isShowingDeleteAlert = true
                                }
                            },
                            setDefaultAction: {
                                Task {
                                    transcriptionModelManager.setDefaultTranscriptionModel(model)
                                }
                            },
                            downloadAction: {
                                if let whisperModel = model as? WhisperModel {
                                    Task { await whisperModelManager.downloadModel(whisperModel) }
                                }
                            },
                            editAction: model.provider == .custom ? { customModel in
                                customModelToEdit = customModel
                            } : nil
                        )
                    }
                    
                    // Import button as a card at the end of the Local list
                    if selectedFilter == .local {
                        HStack(spacing: 8) {
                            Button(action: { presentImportPanel() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Import Local Model…")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(CardBackground(isSelected: false))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            InfoTip(
                                "Add a custom fine-tuned whisper model to use with Nexo Whisper. Select the downloaded .bin file.",
                                learnMoreURL: "\(NexoURLs.docs)/custom-models"
                            )
                            .help("Read more about custom local models")
                        }
                    }
                    
                    if selectedFilter == .custom {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                            Text("Only OpenAI-compatible transcription APIs are supported.")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                        AddCustomModelCardView(
                            customModelManager: customModelManager,
                            editingModel: customModelToEdit
                        ) {
                            // Refresh the models when a new custom model is added
                            transcriptionModelManager.refreshAllAvailableModels()
                            customModelToEdit = nil // Clear editing state
                        }
                    }
                }
            }
        }
        }

    private var localModelStorageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Model Folder")
                        .font(.system(size: 13, weight: .semibold))
                    Text(localModelsRootPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Choose…") {
                    presentModelFolderPanel()
                }

                Button(action: resetModelFolder) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset to Application Support")
            }

            Text("Whisper downloads are saved in a WhisperModels subfolder. Parakeet downloads are saved in a FluidAudio subfolder.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(CardBackground(isSelected: false))
        .cornerRadius(10)
    }



    private var intelMacWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)

            Text("Local models don't work reliably on Intel Macs")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedFilter = .cloud
                }
            }) {
                HStack(spacing: 4) {
                    Text("Use Cloud")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private var filteredModels: [any TranscriptionModel] {
        switch selectedFilter {
        case .recommended:
            return transcriptionModelManager.allAvailableModels.filter {
                let recommendedNames = ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
                return recommendedNames.contains($0.name)
            }.sorted { model1, model2 in
                let recommendedOrder = ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
                let index1 = recommendedOrder.firstIndex(of: model1.name) ?? Int.max
                let index2 = recommendedOrder.firstIndex(of: model2.name) ?? Int.max
                return index1 < index2
            }
        case .local:
            return transcriptionModelManager.allAvailableModels.filter {
                ($0.provider == .whisper || $0.provider == .nativeApple || $0.provider == .fluidAudio)
                    && transcriptionModelManager.isAvailableOnCurrentOS($0)
            }
        case .cloud:
            return transcriptionModelManager.allAvailableModels.filter { CloudProviderRegistry.provider(for: $0.provider) != nil }
        case .custom:
            return transcriptionModelManager.allAvailableModels.filter { $0.provider == .custom }
        }
    }

    // MARK: - Import Panel
    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bin")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.title = "Select a Whisper ggml .bin model"
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await whisperModelManager.importWhisperModel(from: url)
            }
        }
    }

    private func presentModelFolderPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true
        panel.title = "Choose Local Model Download Folder"
        panel.message = "Nexo Whisper will store WhisperModels and FluidAudio folders inside this location."
        panel.directoryURL = LocalModelStorage.rootDirectory

        if panel.runModal() == .OK, let url = panel.url {
            let shouldCopy = shouldCopyExistingWhisperModels()
            LocalModelStorage.saveRootDirectory(url)
            localModelsRootPath = url.standardizedFileURL.path
            whisperModelManager.updateModelsDirectory(
                LocalModelStorage.whisperModelsDirectory,
                copyExistingModels: shouldCopy
            )
            transcriptionModelManager.refreshAllAvailableModels()
        }
    }

    private func shouldCopyExistingWhisperModels() -> Bool {
        guard !whisperModelManager.availableModels.isEmpty else { return false }

        let alert = NSAlert()
        alert.messageText = "Copy existing Whisper models?"
        alert.informativeText = "Nexo Whisper can copy your currently downloaded Whisper models into the new folder so they remain available."
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Don't Copy")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func resetModelFolder() {
        LocalModelStorage.resetRootDirectory()
        localModelsRootPath = LocalModelStorage.rootDirectory.path
        whisperModelManager.updateModelsDirectory(
            LocalModelStorage.whisperModelsDirectory,
            copyExistingModels: false
        )
        transcriptionModelManager.refreshAllAvailableModels()
    }
}
