import SwiftUI

/// Pantalla de configuración de **Magic Clipboard** (sidebar).
/// v1: activar/desactivar, hotkey para abrir el panel, filtro de tipos.
struct MagicClipboardView: View {
    @AppStorage("magicClipboard.enabled") private var enabled = false
    @AppStorage("magicClipboard.includeImages") private var includeImages = true
    @ObservedObject private var service = MagicClipboardService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexoSpacing.lg) {
                NexoHero(
                    title: "Magic Clipboard",
                    subtitle: "A clean, Spotlight-style clipboard history: search what you copied and paste it back in one tap.",
                    systemImage: "doc.on.clipboard.fill",
                    badge: "PREVIEW"
                )

                Toggle(isOn: $enabled) {
                    Text("Enable Magic Clipboard").font(.headline)
                }
                .toggleStyle(.switch)
                .onChange(of: enabled) { _, newValue in
                    Task { @MainActor in MagicClipboardService.shared.isEnabled = newValue }
                }

                if enabled {
                    NexoCard {
                        VStack(alignment: .leading, spacing: NexoSpacing.md) {
                            NexoSectionHeader("Shortcut", systemImage: "keyboard",
                                              subtitle: "The key you press to open the clipboard history.")
                            Divider()
                            LabeledContent("Open clipboard") {
                                ShortcutRecorder(action: .magicClipboard) {}
                                    .controlSize(.small)
                            }
                            Text("Press it anywhere: a clean panel appears with everything you copied, plus an emoji picker.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    NexoCard {
                        VStack(alignment: .leading, spacing: NexoSpacing.md) {
                            NexoSectionHeader("What gets captured", systemImage: "line.3.horizontal.decrease.circle",
                                              subtitle: "Choose which types of content the history keeps.")
                            Divider()
                            Toggle("Capture images", isOn: $includeImages)
                                .toggleStyle(.switch)
                            Text("Turn off to keep only text in the history.")
                                .font(.caption).foregroundStyle(.secondary)

                            Divider()

                            HStack {
                                Text("\(service.history.count) items in history")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear history") { service.clearHistory() }
                                    .controlSize(.small)
                            }
                        }
                    }
                } else {
                    Text("Enable Magic Clipboard to set its shortcut and what it captures.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .nexoPage(maxWidth: 720)
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }
}
