import SwiftUI

/// Configuración del PANEL de respuesta de Magic Selection:
/// - Chips de acción: mostrar/ocultar, reordenar y crear chips CUSTOM.
/// - Traducir: idioma preferido + auto-detección.
/// - Auto-cierre del panel.
struct MagicPanelSettingsView: View {
    @ObservedObject private var chipStore = MagicChipStore.shared

    @AppStorage("magicSelection.panelAutoHideSeconds") private var autoHideSeconds: Double = 0
    @AppStorage("magicSelection.translateLanguage") private var translateLanguage = "English"
    @AppStorage("magicSelection.translateAutoDetect") private var translateAutoDetect = true
    @AppStorage("magicSelection.confirmActions") private var confirmActions = true
    @AppStorage("magicSelection.messagingApp") private var messagingApp = "whatsapp"
    @AppStorage("magicSelection.visionFallback") private var visionFallback = true

    @State private var showingAddChip = false

    var body: some View {
        GroupBox(label: Label("Response panel", systemImage: "rectangle.and.text.magnifyingglass")) {
            VStack(alignment: .leading, spacing: 14) {
                chipsSection
                Divider()
                translateSection
                Divider()
                autoHideSection
                Divider()
                actionsSection
                Divider()
                chromeNote
            }
            .padding(6)
        }
        .sheet(isPresented: $showingAddChip) {
            MagicChipEditor { chip in chipStore.add(chip) }
        }
    }

    // ── Chips ───────────────────────────────────────────────────────────

    private var chipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Action buttons").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    showingAddChip = true
                } label: {
                    Label("Add", systemImage: "plus.circle")
                }
                .controlSize(.small)
                Button {
                    chipStore.resetToDefaults()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .help("Restore the default chips")
            }
            Text("Choose which ones you see in the panel, reorder them or create your own.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(Array(chipStore.chips.enumerated()), id: \.element.id) { index, chip in
                chipRow(chip, index: index)
                if index < chipStore.chips.count - 1 { Divider().opacity(0.4) }
            }
        }
    }

    private func chipRow(_ chip: MagicChip, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: chip.systemImage)
                .frame(width: 18)
                .foregroundStyle(.purple)
            Text(AppText.t(chip.title)).font(.system(size: 12))
            if chip.isCustom {
                Text("custom")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.purple.opacity(0.18)))
                    .foregroundStyle(.purple)
            }
            Spacer()

            // Reordenar
            Button { chipStore.move(from: [index], to: index - 1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless).controlSize(.small)
            .disabled(index == 0)

            Button { chipStore.move(from: [index], to: index + 2) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless).controlSize(.small)
            .disabled(index == chipStore.chips.count - 1)

            // Borrar (solo custom)
            if chip.isCustom {
                Button { chipStore.remove(chip) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).controlSize(.small)
                .foregroundStyle(.red)
            }

            // Mostrar / ocultar
            Toggle("", isOn: Binding(
                get: { chip.enabled },
                set: { _ in chipStore.toggle(chip) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // ── Traducir ────────────────────────────────────────────────────────

    private var translateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Translate").font(.system(size: 12, weight: .semibold))
            HStack {
                Text("Preferred language")
                Spacer()
                Picker("", selection: $translateLanguage) {
                    ForEach(MagicTranslation.languages, id: \.self) { Text(AppText.t($0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Toggle("Detect the target language automatically", isOn: $translateAutoDetect)
                .toggleStyle(.switch)
            Text(translateAutoDetect
                 ? "If the text is already in your preferred language, it translates to your language; otherwise, to the preferred one. You can still pick another language from the chip."
                 : "Always translates to the preferred language. You can pick another one from the chip.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // ── Nota Chrome / Electron ──────────────────────────────────────────

    private var chromeNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("On non-native Mac apps (Chrome, Slack, Discord, VS Code and others based on Chromium/Electron), due to a macOS limitation, Magic can't detect the text field. To paste the result, tap the **“Replace text”** button in the panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Acciones (confirmar + mensajería) ───────────────────────────────

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions").font(.system(size: 12, weight: .semibold))
            Toggle("Confirm events without a date before creating", isOn: $confirmActions)
                .toggleStyle(.switch)
            Text("If you ask for an event and no date is detected, it shows a form to set it. The rest of the actions (email, message, map, reminder, event with a date) run directly.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Default messaging app")
                Spacer()
                Picker("", selection: $messagingApp) {
                    Text("WhatsApp").tag("whatsapp")
                    Text("Telegram").tag("telegram")
                    Text("iMessage").tag("imessage")
                }
                .labelsHidden()
                .frame(width: 150)
            }
            Text("For “send this as a message”. The chosen app's icon appears in the panel.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle("Read text under the cursor with vision (OCR)", isOn: $visionFallback)
                .toggleStyle(.switch)
            Text("When an app doesn't expose its text (terminals, images, PDFs), Magic captures the area under the cursor and reads it with Apple's on-device recognition. Free and private.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // ── Auto-cierre ─────────────────────────────────────────────────────

    private var autoHideSection: some View {
        HStack {
            Text("The panel closes on its own")
            Spacer()
            Picker("", selection: $autoHideSeconds) {
                Text("Never").tag(0.0)
                Text("30 s").tag(30.0)
                Text("1 min").tag(60.0)
                Text("2 min").tag(120.0)
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }
}

// ── Editor de chip custom ────────────────────────────────────────────────

private struct MagicChipEditor: View {
    let onSave: (MagicChip) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var command = ""
    @State private var icon = "wand.and.stars"

    private let icons = [
        "wand.and.stars", "sparkles", "text.bubble", "quote.bubble", "pencil",
        "bolt", "star", "heart", "flame", "leaf", "globe", "list.bullet",
        "face.smiling", "briefcase", "graduationcap", "character.bubble"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New chip").font(.title3).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Formal tone", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instruction (what you ask the AI)").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Rewrite this in a formal, professional tone.", text: $command, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(icons, id: \.self) { sym in
                        Image(systemName: sym)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(icon == sym ? Color.purple.opacity(0.25) : Color.gray.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(icon == sym ? Color.purple : .clear, lineWidth: 1.5)
                            )
                            .onTapGesture { icon = sym }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty, !c.isEmpty else { return }
                    onSave(MagicChip(title: t, systemImage: icon, command: c, isCustom: true))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
