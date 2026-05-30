import SwiftUI

/// Configuración del PANEL de respuesta de Magic Selection:
/// - Chips de acción: mostrar/ocultar, reordenar y crear chips CUSTOM.
/// - Traducir: idioma preferido + auto-detección.
/// - Auto-cierre del panel.
struct MagicPanelSettingsView: View {
    @ObservedObject private var chipStore = MagicChipStore.shared

    @AppStorage("magicSelection.panelAutoHideSeconds") private var autoHideSeconds: Double = 0
    @AppStorage("magicSelection.translateLanguage") private var translateLanguage = "Inglés"
    @AppStorage("magicSelection.translateAutoDetect") private var translateAutoDetect = true
    @AppStorage("magicSelection.confirmActions") private var confirmActions = true
    @AppStorage("magicSelection.messagingApp") private var messagingApp = "whatsapp"

    @State private var showingAddChip = false

    var body: some View {
        GroupBox(label: Label("Panel de respuesta", systemImage: "rectangle.and.text.magnifyingglass")) {
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
                Text("Botones de acción").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    showingAddChip = true
                } label: {
                    Label("Agregar", systemImage: "plus.circle")
                }
                .controlSize(.small)
                Button {
                    chipStore.resetToDefaults()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .help("Restaurar los chips por defecto")
            }
            Text("Elegí cuáles ves en el panel, ordenalos o creá los tuyos.")
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
            Text(chip.title).font(.system(size: 12))
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
            Text("Traducir").font(.system(size: 12, weight: .semibold))
            HStack {
                Text("Idioma preferido")
                Spacer()
                Picker("", selection: $translateLanguage) {
                    ForEach(MagicTranslation.languages, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Toggle("Detectar el idioma de destino automáticamente", isOn: $translateAutoDetect)
                .toggleStyle(.switch)
            Text(translateAutoDetect
                 ? "Si el texto ya está en tu idioma preferido, lo traduce a tu idioma; si no, al preferido. Igual podés elegir otro idioma desde el chip."
                 : "Siempre traduce al idioma preferido. Podés elegir otro puntual desde el chip.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // ── Nota Chrome / Electron ──────────────────────────────────────────

    private var chromeNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("En apps que no son nativas de Mac (Chrome, Slack, Discord, VS Code y otras basadas en Chromium/Electron), por una limitación del propio macOS, Magic no puede detectar el campo de texto. Para pegar el resultado, tocá el botón **“Reemplazar texto”** del panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Acciones (confirmar + mensajería) ───────────────────────────────

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acciones").font(.system(size: 12, weight: .semibold))
            Toggle("Confirmar antes de crear (evento / nota / recordatorio)", isOn: $confirmActions)
                .toggleStyle(.switch)
            Text("Muestra los datos preseleccionados para revisar y editar antes de crear.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("App de mensajería por defecto")
                Spacer()
                Picker("", selection: $messagingApp) {
                    Text("WhatsApp").tag("whatsapp")
                    Text("Telegram").tag("telegram")
                    Text("Mensajes").tag("imessage")
                }
                .labelsHidden()
                .frame(width: 150)
            }
            Text("Para “mandá esto por mensaje”. El ícono de la app elegida aparece en el panel.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // ── Auto-cierre ─────────────────────────────────────────────────────

    private var autoHideSection: some View {
        HStack {
            Text("El panel se cierra solo")
            Spacer()
            Picker("", selection: $autoHideSeconds) {
                Text("Nunca").tag(0.0)
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
            Text("Nuevo chip").font(.title3).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Nombre").font(.caption).foregroundStyle(.secondary)
                TextField("Ej: Tono formal", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instrucción (lo que se le pide a la IA)").font(.caption).foregroundStyle(.secondary)
                TextField("Ej: Reescribí esto en un tono formal y profesional.", text: $command, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Ícono").font(.caption).foregroundStyle(.secondary)
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
                Button("Cancelar") { dismiss() }
                Button("Agregar") {
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
