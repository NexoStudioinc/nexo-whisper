import SwiftUI

/// Settings UI del feature **Magic Selection** (F1 — preview).
///
/// Permite activar/desactivar el feature, ajustar la sensibilidad del
/// detector de wiggle y disparar un test manual.
///
/// En F1 NO hay integración con el recorder todavía — el botón "Test now"
/// solo loguea el contexto extraído a Console.app. Sirve para que el user
/// pueda verificar que el feature está captando bien el texto bajo el cursor
/// antes de meter el flow completo en F2.
struct MagicSelectionSection: View {

    // ── Master toggles ─────────────────────────────────────────────────
    @AppStorage("magicSelection.enabled") private var enabled = false
    @AppStorage("magicSelection.wiggleEnabled") private var wiggleEnabled = true

    // ── Tuning del detector ─────────────────────────────────────────────
    @AppStorage("magicSelection.directionChangesThreshold") private var directionChangesThreshold = 5
    @AppStorage("magicSelection.minVelocityPxPerSec") private var minVelocityPxPerSec: Double = 250
    @AppStorage("magicSelection.windowDurationMs") private var windowDurationMs = 400
    @AppStorage("magicSelection.cooldownSec") private var cooldownSec: Double = 2.0

    // ── Estado UI ──────────────────────────────────────────────────────
    @State private var lastTestResult: String = ""
    @State private var showInstructions = false

    var body: some View {
        Section {
            // Master toggle
            Toggle("Activar Magic Selection (preview)", isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    Task { @MainActor in
                        MagicSelectionService.shared.isEnabled = newValue
                    }
                }

            if enabled {
                // Toggle de activación por wiggle
                Toggle("Activar con gesto wiggle del mouse", isOn: $wiggleEnabled)
                    .onChange(of: wiggleEnabled) { _, newValue in
                        Task { @MainActor in
                            MagicSelectionService.shared.isWiggleEnabled = newValue
                        }
                    }
                    .padding(.leading, 24)

                if wiggleEnabled {
                    // Sliders de tuning
                    VStack(alignment: .leading, spacing: 12) {
                        sliderRow(
                            label: "Sensibilidad (cambios de dirección)",
                            value: Binding(
                                get: { Double(directionChangesThreshold) },
                                set: { directionChangesThreshold = Int($0) }
                            ),
                            range: 3...7,
                            step: 1,
                            display: "\(directionChangesThreshold) cambios"
                        )

                        sliderRow(
                            label: "Velocidad mínima del wiggle",
                            value: $minVelocityPxPerSec,
                            range: 100...500,
                            step: 25,
                            display: "\(Int(minVelocityPxPerSec)) px/s"
                        )

                        sliderRow(
                            label: "Ventana de detección",
                            value: Binding(
                                get: { Double(windowDurationMs) },
                                set: { windowDurationMs = Int($0) }
                            ),
                            range: 200...800,
                            step: 50,
                            display: "\(windowDurationMs) ms"
                        )

                        sliderRow(
                            label: "Cooldown entre activaciones",
                            value: $cooldownSec,
                            range: 1.0...5.0,
                            step: 0.5,
                            display: String(format: "%.1f s", cooldownSec)
                        )
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }

                // Botón de test manual
                HStack {
                    Button {
                        triggerTestNow()
                    } label: {
                        Label("Probar ahora (toma contexto bajo el cursor)", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button {
                        showInstructions.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Ver instrucciones")
                }

                // Resultado del último test
                if !lastTestResult.isEmpty {
                    GroupBox {
                        Text(lastTestResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                // Instrucciones desplegables
                if showInstructions {
                    instructionsView
                }
            }
        } header: {
            HStack(spacing: 6) {
                Label("Magic Selection", systemImage: "wand.and.stars")
                Text("PREVIEW")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.purple.opacity(0.2))
                    )
                    .foregroundStyle(.purple)
            }
        } footer: {
            if enabled {
                Text("Feature experimental. Por ahora solo detecta el wiggle y extrae el texto bajo el cursor — el resultado se loguea en Console.app. La integración con grabación + IA llega en la próxima versión.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ── Subviews ───────────────────────────────────────────────────────

    @ViewBuilder
    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(display)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var instructionsView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cómo funciona el wiggle")
                    .font(.headline)

                Text("1. **Encendé** el feature con el toggle de arriba.\n2. Posicionate sobre cualquier texto en cualquier app (Mail, Slack, Notion, una celda de Excel, un mensaje de WhatsApp, etc.).\n3. **Sacudí el mouse rápido de izquierda a derecha** sin moverlo más allá de unos 100px. Necesita varios cambios de dirección seguidos para activar (esto evita falsos positivos con movimientos normales).\n4. Si el sensor detecta el wiggle, vas a ver en **Console.app** (filtrá por subsystem `com.prakashjoshipax.voiceink`) un log:")
                    .font(.callout)

                Text("🪄 Magic Selection triggered by wiggle at (X, Y)\nContext: MagicContext[app=…, role=…, text=\"…\"]")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(6)

                Text("Si nunca dispara, bajá la **sensibilidad** o la **velocidad mínima**. Si se activa demasiado seguido sin querer, subílas.")
                    .font(.callout)
            }
            .padding(4)
        }
    }

    // ── Acciones ───────────────────────────────────────────────────────

    private func triggerTestNow() {
        let location = NSEvent.mouseLocation
        let context = MagicContextExtractor.extract(at: location)

        var lines: [String] = []
        lines.append("📍 Cursor: (\(Int(location.x)), \(Int(location.y)))")
        if let app = context.appName { lines.append("📱 App: \(app)") }
        if let role = context.role { lines.append("🎭 Role: \(role)") }
        if let sel = context.selectedText, !sel.isEmpty {
            lines.append("✂️ Selección: \"\(sel.prefix(200))\"")
        }
        if let el = context.elementText, !el.isEmpty {
            lines.append("🎯 Elemento bajo cursor: \"\(el.prefix(200))\"")
        }
        if context.bestText == nil {
            lines.append("⚠️ No se pudo extraer texto. ¿Estás sobre un elemento con texto? ¿Permisos de Accesibilidad activos?")
        }

        lastTestResult = lines.joined(separator: "\n")
    }
}
