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

    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                Toggle(isOn: $enabled) {
                    Text("Activar Magic").font(.headline)
                }
                .toggleStyle(.switch)
                .onChange(of: enabled) { _, newValue in
                    Task { @MainActor in MagicSelectionService.shared.isEnabled = newValue }
                }

                if enabled {
                    activationCard
                    MagicPanelSettingsView()
                    advancedCard
                } else {
                    Text("Activá Magic para configurar los botones de acción, la traducción y el comportamiento del panel.")
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
        HStack(spacing: 12) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 26))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.96),
                                            Color(red: 0.36, green: 0.80, blue: 0.95)],
                                   startPoint: .leading, endPoint: .trailing)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Magic").font(.title2).bold()
                    Text("PREVIEW")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.purple.opacity(0.2)))
                        .foregroundStyle(.purple)
                }
                Text("Seleccioná texto, dictá o tocá un botón, y la IA actúa sobre eso al instante.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // ── Activación ──────────────────────────────────────────────────────

    private var activationCard: some View {
        GroupBox(label: Label("Activación", systemImage: "hand.tap")) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Atajo de teclado") {
                    ShortcutRecorder(action: .magicSelection) {}
                        .controlSize(.small)
                }

                if let shortcut = ShortcutStore.shortcut(for: .magicSelection),
                   shortcut.kind == .modifierOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("El atajo (\(shortcut.displayString)) es solo un modificador. Combinalo con una tecla, ej. ⌥M o ⌃⌥Z.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle("Activar también con el gesto wiggle del mouse", isOn: $wiggleEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: wiggleEnabled) { _, newValue in
                        Task { @MainActor in MagicSelectionService.shared.isWiggleEnabled = newValue }
                    }
                Text("Sacudí el mouse de lado a lado para activar. Mantené ⌥ Option durante el wiggle para el modo continuo (escucha por silencio).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    // ── Avanzado (sensibilidad del wiggle) ──────────────────────────────

    private var advancedCard: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow("Sensibilidad (cambios de dirección)",
                              value: Binding(get: { Double(directionChangesThreshold) },
                                             set: { directionChangesThreshold = Int($0) }),
                              range: 3...7, step: 1, display: "\(directionChangesThreshold) cambios")
                    sliderRow("Velocidad mínima del wiggle",
                              value: $minVelocityPxPerSec,
                              range: 100...500, step: 25, display: "\(Int(minVelocityPxPerSec)) px/s")
                    sliderRow("Ventana de detección",
                              value: Binding(get: { Double(windowDurationMs) },
                                             set: { windowDurationMs = Int($0) }),
                              range: 200...800, step: 50, display: "\(windowDurationMs) ms")
                    sliderRow("Cooldown entre activaciones",
                              value: $cooldownSec,
                              range: 1.0...5.0, step: 0.5, display: String(format: "%.1f s", cooldownSec))
                }
                .padding(.top, 8)
            } label: {
                Label("Sensibilidad del wiggle (avanzado)", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(6)
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>,
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
