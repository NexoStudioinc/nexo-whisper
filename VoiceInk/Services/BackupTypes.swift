import Foundation
import KeyboardShortcuts

enum BackupCategory: String, CaseIterable, Hashable {
    case general
    case prompts
    case powerMode
    case dictionary
    case customModels

    var title: String {
        switch self {
        case .general:
            return "General Settings"
        case .prompts:
            return "Custom Prompts"
        case .powerMode:
            return "Power Mode"
        case .dictionary:
            return "Dictionary"
        case .customModels:
            return "Custom Model Definitions"
        }
    }
}

struct CustomModelBackup: Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let apiEndpoint: String
    let modelName: String
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
    let apiKey: String?

    init(model: CustomCloudModel) {
        self.id = model.id
        self.name = model.name
        self.displayName = model.displayName
        self.description = model.description
        self.apiEndpoint = model.apiEndpoint
        self.modelName = model.modelName
        self.isMultilingualModel = model.isMultilingualModel
        self.supportedLanguages = model.supportedLanguages
        self.apiKey = nil
    }

    func makeModel() -> CustomCloudModel {
        let model = CustomCloudModel(
            id: id,
            name: name,
            displayName: displayName,
            description: description,
            apiEndpoint: apiEndpoint,
            modelName: modelName,
            isMultilingual: isMultilingualModel,
            supportedLanguages: supportedLanguages
        )

        if let apiKey, !apiKey.isEmpty {
            APIKeyManager.shared.saveCustomModelAPIKey(apiKey, forModelId: id)
        }

        return model
    }
}

struct GeneralBackup: Codable {
    let toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?
    let toggleMiniRecorderShortcut2: KeyboardShortcuts.Shortcut?
    let pasteLastTranscriptionShortcut: KeyboardShortcuts.Shortcut?
    let pasteLastEnhancementShortcut: KeyboardShortcuts.Shortcut?
    let retryLastTranscriptionShortcut: KeyboardShortcuts.Shortcut?
    let cancelRecorderShortcut: KeyboardShortcuts.Shortcut?
    let openHistoryWindowShortcut: KeyboardShortcuts.Shortcut?
    let quickAddToDictionaryShortcut: KeyboardShortcuts.Shortcut?
    let toggleEnhancementShortcut: KeyboardShortcuts.Shortcut?
    let selectedHotkey1RawValue: String?
    let selectedHotkey2RawValue: String?
    let hotkeyMode1RawValue: String?
    let hotkeyMode2RawValue: String?
    let isMiddleClickToggleEnabled: Bool?
    let middleClickActivationDelay: Int?
    let launchAtLoginEnabled: Bool?
    let isMenuBarOnly: Bool?
    let recorderType: String?
    let isTranscriptionCleanupEnabled: Bool?
    let transcriptionRetentionMinutes: Int?
    let isAudioCleanupEnabled: Bool?
    let audioRetentionPeriod: Int?

    let isSoundFeedbackEnabled: Bool?
    let isSystemMuteEnabled: Bool?
    let isPauseMediaEnabled: Bool?
    let audioResumptionDelay: Double?
    let isTextFormattingEnabled: Bool?
    let removePunctuation: Bool?
    let lowercaseTranscription: Bool?
    let isExperimentalFeaturesEnabled: Bool?
    let restoreClipboardAfterPaste: Bool?
    let clipboardRestoreDelay: Double?
    let useAppleScriptPaste: Bool?
}

struct WordBackup: Codable {
    let word: String
}

struct BackupFile: Codable {
    let version: String
    let customPrompts: [CustomPrompt]
    let powerModeConfigs: [PowerModeConfig]
    let powerModeShortcuts: [String: KeyboardShortcuts.Shortcut]?
    let vocabularyWords: [WordBackup]?
    let wordReplacements: [String: String]?
    let generalSettings: GeneralBackup?
    let customEmojis: [String]?
    let customCloudModels: [CustomModelBackup]?
}
