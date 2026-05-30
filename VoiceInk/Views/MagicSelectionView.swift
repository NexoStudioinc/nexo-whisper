import SwiftUI

/// Pantalla dedicada de **Magic** en el sidebar. Nuclea TODA la configuración
/// del feature (activación, chips, traducir, auto-cierre, sensibilidad), para
/// que crezca acá sin entorpecer los Ajustes generales. En Ajustes queda solo
/// el toggle de activar/desactivar.
struct MagicSelectionView: View {
    @AppStorage("magicSelection.enabled") private var enabled = false
    @AppStorage("magicSelection.wiggleEnabled") private var wiggleEnabled = true

    @AppStorage("magicSelection.directionChangesThreshold") private var directionChangesThreshold = 3
    @AppStorage("magicSelection.minVelocityPxPerSec") private var minVelocityPxPerSec: Double = 150
    @AppStorage("magicSelection.windowDurationMs") private var windowDurationMs = 600
    @AppStorage("magicSelection.cooldownSec") private var cooldownSec: Double = 2.0

    @AppStorage("magicSelection.continuousModifier") private var continuousModifier = "option"
    @AppStorage("magicSelection.transcribeModifier") private var transcribeModifier = "control"
    @AppStorage("magicSelection.replaceDirectModifier") private var replaceDirectModifier = "shift"

    private let modifiers: [(id: String, label: String)] = [
        ("option", "⌥ Option"), ("control", "⌃ Control"),
        ("command", "⌘ Command"), ("shift", "⇧ Shift")
    ]

    @State private var showAdvanced = false
    @State private var auraColor: Color = MagicAura.customColor ?? MagicAura.defaultPrimary
    @State private var usingCustomAura: Bool = MagicAura.customColor != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                Toggle(isOn: $enabled) {
                    Text("Enable Magic Aura").font(.headline)
                }
                .toggleStyle(.switch)
                .onChange(of: enabled) { _, newValue in
                    Task { @MainActor in MagicSelectionService.shared.isEnabled = newValue }
                }

                if enabled {
                    activationCard
                    auraCard
                    MagicPanelSettingsView()
                    advancedCard
                } else {
                    Text("Enable Magic to configure the action buttons, translation and panel behavior.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ── Encabezado ──────────────────────────────────────────────────────

    private var hero: some View {
        NexoHero(
            title: "Magic Aura",
            subtitle: "Select text, dictate or tap a button, and the AI acts on it instantly.",
            systemImage: "cursorarrow.rays",
            badge: "PREVIEW"
        )
    }

    // ── Activación ──────────────────────────────────────────────────────

    private var activationCard: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("Activation", systemImage: "hand.tap",
                                  subtitle: "How you trigger Magic Aura and what each modifier key does.")
                Divider()

                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorder(action: .magicSelection) {}
                        .controlSize(.small)
                }

                if let shortcut = ShortcutStore.shortcut(for: .magicSelection),
                   shortcut.kind == .modifierOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("The shortcut (\(shortcut.displayString)) is only a modifier. Combine it with a key, e.g. ⌥M or ⌃⌥Z.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle("Also activate with the mouse wiggle gesture", isOn: $wiggleEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: wiggleEnabled) { _, newValue in
                        Task { @MainActor in MagicSelectionService.shared.isWiggleEnabled = newValue }
                    }
                Text("Shake the mouse side to side to activate Magic.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                // Modificadores de los modos (configurables, no hardcodeados).
                modifierRow(
                    title: "Key for continuous mode",
                    help: "Hold this key while you wiggle so Magic keeps listening in a loop (it cuts each command on silence). Release the key and keep giving commands until you close with Esc.",
                    selection: $continuousModifier
                )
                modifierRow(
                    title: "Key for transcriber mode",
                    help: "Hold this key during the wiggle to dictate text: it records your voice, transcribes it (and enhances it if you have AI enhancement enabled) and pastes it where the cursor is. Like regular dictation, but triggered with the wiggle.",
                    selection: $transcribeModifier
                )
                modifierRow(
                    title: "Key for direct replace",
                    help: "Hold this key during the wiggle so the result is pasted DIRECTLY over the selection, without opening the panel (\"I trust the answer\" mode).",
                    selection: $replaceDirectModifier
                )

                if let conflict = modifierConflict {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("The \(conflict) key is assigned to more than one mode. Choose different keys for each.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Si dos o más modos comparten el mismo modificador (≠ Ninguna), devuelve
    /// su etiqueta para avisar del conflicto.
    private var modifierConflict: String? {
        let used = [continuousModifier, transcribeModifier, replaceDirectModifier].filter { $0 != "none" }
        let dup = used.first { m in used.filter { $0 == m }.count > 1 }
        return dup.flatMap { id in modifiers.first { $0.id == id }?.label }
    }

    private func modifierRow(title: LocalizedStringKey, help: LocalizedStringKey, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Picker("", selection: selection) {
                    Text("None").tag("none")
                    ForEach(modifiers, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            // Descripción SIEMPRE visible (el tooltip por hover no se notaba).
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(help)
    }

    // ── Aura (color del glow del cursor) ────────────────────────────────

    private var auraCard: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.sm) {
                NexoSectionHeader("Aura", systemImage: "paintpalette",
                                  subtitle: "The glow around the cursor while Magic Aura is listening.")
                Divider()
                HStack {
                    // Vista previa del aura.
                    Circle()
                        .fill(RadialGradient(colors: [auraColor, auraColor.opacity(0)],
                                             center: .center, startRadius: 1, endRadius: 18))
                        .frame(width: 34, height: 34)
                    Text("Aura color")
                    Spacer()
                    ColorPicker("", selection: $auraColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: auraColor) { _, newColor in
                            MagicAura.setColor(newColor)
                            usingCustomAura = true
                        }
                }
                Text("The halo around the cursor when Magic Aura is active. Violet → cyan by default.")
                    .font(.caption).foregroundStyle(.secondary)
                if usingCustomAura {
                    Button("Restore default gradient") {
                        MagicAura.setColor(nil)
                        usingCustomAura = false
                        auraColor = MagicAura.defaultPrimary
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // ── Avanzado (sensibilidad del wiggle) ──────────────────────────────

    private var advancedCard: some View {
        NexoCard {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow("Sensitivity (direction changes)",
                              value: Binding(get: { Double(directionChangesThreshold) },
                                             set: { directionChangesThreshold = Int($0) }),
                              range: 3...7, step: 1, display: String(localized: "\(directionChangesThreshold) changes"))
                    sliderRow("Minimum wiggle speed",
                              value: $minVelocityPxPerSec,
                              range: 100...500, step: 25, display: "\(Int(minVelocityPxPerSec)) px/s")
                    sliderRow("Detection window",
                              value: Binding(get: { Double(windowDurationMs) },
                                             set: { windowDurationMs = Int($0) }),
                              range: 200...800, step: 50, display: "\(windowDurationMs) ms")
                    sliderRow("Cooldown between activations",
                              value: $cooldownSec,
                              range: 1.0...5.0, step: 0.5, display: String(format: "%.1f s", cooldownSec))
                }
                .padding(.top, 8)
            } label: {
                Label("Wiggle sensitivity (advanced)", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(6)
        }
    }

    private func sliderRow(_ label: LocalizedStringKey, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text(display).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
