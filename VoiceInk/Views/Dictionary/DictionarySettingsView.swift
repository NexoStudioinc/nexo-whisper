import SwiftUI
import SwiftData

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: DictionarySection = .replacements
    @State private var isShowingSettings = false
    let whisperPrompt: WhisperPrompt
    
    enum DictionarySection: String, CaseIterable {
        case replacements = "Word Replacements"
        case spellings = "Vocabulary"

        // LocalizedStringKey en vez de String para que SwiftUI auto-localice
        // los literales contra xcstrings. Si fueran String SwiftUI los pasaría
        // como variables y nunca traduciría.
        var titleKey: LocalizedStringKey {
            switch self {
            case .replacements: return "Word Replacements"
            case .spellings:    return "Vocabulary"
            }
        }

        var descriptionKey: LocalizedStringKey {
            switch self {
            case .spellings:
                return "Add words to help Nexo Whisper recognize them properly"
            case .replacements:
                return "Automatically replace specific words/phrases with custom formatted text"
            }
        }

        var icon: String {
            switch self {
            case .spellings:
                return "character.book.closed.fill"
            case .replacements:
                return "arrow.2.squarepath"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexoSpacing.lg) {
                heroSection
                sectionSelector
                selectedSectionContent
            }
            .nexoPage()
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .slidingPanel(isPresented: $isShowingSettings, width: 400) {
            DictionarySettingsPanel {
                withAnimation(.smooth(duration: 0.3)) {
                    isShowingSettings = false
                }
            }
        }
    }

    private var heroSection: some View {
        NexoHero(
            title: "Dictionary Settings",
            subtitle: "Teach Nexo Whisper your vocabulary and word replacements to improve transcription accuracy.",
            systemImage: "brain.filled.head.profile"
        )
    }

    private var sectionSelector: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader(title: "Select Section", systemImage: "square.grid.2x2",
                                  subtitle: "Choose what you want to manage.") {
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isShowingSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isShowingSettings ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dictionary settings")
                }
                Divider()
                HStack(spacing: NexoSpacing.lg) {
                    ForEach(DictionarySection.allCases, id: \.self) { section in
                        SectionCard(
                            section: section,
                            isSelected: selectedSection == section,
                            action: { selectedSection = section }
                        )
                    }
                }
            }
        }
    }

    private var selectedSectionContent: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader(selectedSection.titleKey, systemImage: selectedSection.icon,
                                  subtitle: selectedSection.descriptionKey)
                Divider()
                switch selectedSection {
                case .spellings:
                    VocabularyView(whisperPrompt: whisperPrompt)
                case .replacements:
                    WordReplacementView()
                }
            }
        }
    }
}

struct SectionCard: View {
    let section: DictionarySettingsView.DictionarySection
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.titleKey)
                        .font(.headline)

                    Text(section.descriptionKey)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
} 
