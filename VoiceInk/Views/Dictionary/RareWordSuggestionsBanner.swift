import SwiftUI
import SwiftData

/// Banner que muestra palabras "raras" detectadas en transcripciones recientes
/// y le permite al usuario agregarlas al vocabulario con un clic, rechazarlas
/// para no volver a sugerirlas, o dejarlas pasar por esta vez.
///
/// Solo se renderiza si hay sugerencias pendientes (`pendingSuggestions` no
/// vacío). Pensado para vivir arriba de `VocabularyView`.
struct RareWordSuggestionsBanner: View {
    @ObservedObject private var tracker = RareWordTracker.shared
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if tracker.pendingSuggestions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text("Suggestions for your vocabulary")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("Repeated unknown words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(tracker.pendingSuggestions, id: \.self) { word in
                    HStack(spacing: 8) {
                        Text(word)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            tracker.accept(word: word, modelContext: modelContext)
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Add to vocabulary")

                        Button {
                            tracker.dismiss(word: word)
                        } label: {
                            Label("Not now", systemImage: "clock.arrow.circlepath")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Not now")

                        Button {
                            tracker.reject(word: word)
                        } label: {
                            Label("Never suggest", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Never suggest")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.yellow.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.yellow.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }
}
