import SwiftUI
import KeyboardShortcuts

struct DictionarySettingsPanel: View {
    @AppStorage("autoLearnVocabulary") private var autoLearnVocabulary: Bool = true
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Dictionary Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
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
            Form {
                Section {
                    Toggle(isOn: $autoLearnVocabulary) {
                        HStack(spacing: 4) {
                            Text("Auto Learn Vocabulary")
                            InfoTip("Automatically adds corrected words to your vocabulary when you edit a transcription after pasting.")
                        }
                    }
                    .toggleStyle(.switch)
                } header: {
                    Text("Auto Learn")
                }

                Section {
                    LabeledContent("Quick Add to Dictionary") {
                        KeyboardShortcuts.Recorder(for: .quickAddToDictionary)
                            .controlSize(.small)
                    }
                } header: {
                    Text("Shortcuts")
                }

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
