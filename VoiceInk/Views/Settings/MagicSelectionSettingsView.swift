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

    // ── Tuning del detector (defaults más laxos para que dispare más fácil) ─
    @AppStorage("magicSelection.directionChangesThreshold") private var directionChangesThreshold = 3
    @AppStorage("magicSelection.minVelocityPxPerSec") private var minVelocityPxPerSec: Double = 150
    @AppStorage("magicSelection.windowDurationMs") private var windowDurationMs = 600
    @AppStorage("magicSelection.cooldownSec") private var cooldownSec: Double = 2.0

    // ── Estado UI ──────────────────────────────────────────────────────
    @State private var lastTestResult: String = ""
    @State private var showInstructions = false
    @State private var diagnostics: String = ""

    private func refreshDiagnostics() {
        var lines: [String] = []

        // 1. Permisos
        let axTrusted = AXIsProcessTrusted()
        lines.append("Accessibility permission: \(axTrusted ? "✅ Granted" : "❌ MISSING")")

        // 2. Estado del detector
        let status = MagicSelectionService.shared.detectorStatus
        switch status {
        case .notStarted:
            lines.append("Detector status: ⚪ Not started (toggle the master switch above)")
        case .running:
            lines.append("Detector status: ✅ RUNNING (waiting for wiggle)")
        case .disabledByUser:
            lines.append("Detector status: ⚪ Disabled by user")
        case .startFailed(let reason):
            lines.append("Detector status: ❌ START FAILED — \(reason)")
        }

        // 3. Hotkey configurado
        if let shortcut = ShortcutStore.shortcut(for: .magicSelection) {
            lines.append("Hotkey: ✅ \(shortcut.displayString)")
        } else {
            lines.append("Hotkey: ⚪ Not configured (click el campo de atajo arriba)")
        }

        diagnostics = lines.joined(separator: "\n")
    }

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
                // Hotkey configurable (la forma más confiable de activación)
                LabeledContent("Atajo de teclado para activar") {
                    ShortcutRecorder(action: .magicSelection) {
                        // No-op: el ShortcutMonitor se refresca solo via
                        // notification de ShortcutStore.shortcutDidChange.
                        // Refrescamos el diagnóstico para que se vea el cambio.
                        refreshDiagnostics()
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 24)

                // Warning si el hotkey configurado es solo un modificador
                // (no funciona como atajo regular — necesita combo con tecla)
                if let shortcut = ShortcutStore.shortcut(for: .magicSelection),
                   shortcut.kind == .modifierOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("El atajo configurado (\(shortcut.displayString)) es solo un modificador. Para que dispare, combinalo con una tecla — por ejemplo ⌥M (Option+M) o ⌃⌥Z.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                }

                // Toggle de activación por wiggle
                Toggle("Activar también con gesto wiggle del mouse", isOn: $wiggleEnabled)
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

                    Button {
                        Task { @MainActor in
                            MagicSelectionService.shared.triggerManually()
                            // Refrescamos el resultado en pantalla para que se vea
                            // que el trigger pasó (sin solo loguear a Console)
                            triggerTestNow()
                            lastTestResult = "🎯 TRIGGER SIMULADO disparado.\n\n" + lastTestResult
                        }
                    } label: {
                        Label("Simular trigger", systemImage: "wand.and.stars.inverse")
                    }
                    .help("Simula que se disparó el wiggle o el hotkey — útil para confirmar que el pipeline completo funciona")

                    Spacer()

                    Button {
                        showInstructions.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Ver instrucciones")
                }

                // Configuración del panel de respuesta (chips, traducir, auto-cierre)
                MagicPanelSettingsView()

                // Panel de diagnóstico
                GroupBox(label: HStack {
                    Label("Diagnóstico", systemImage: "stethoscope")
                    Spacer()
                    Button {
                        refreshDiagnostics()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refrescar diagnóstico")
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        if diagnostics.isEmpty {
                            Text("Click el botón ↻ para chequear el estado")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(diagnostics)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 8) {
                            Button("Force restart detector") {
                                Task { @MainActor in
                                    MagicSelectionService.shared.stop()
                                    MagicSelectionService.shared.startIfNeeded()
                                    refreshDiagnostics()
                                }
                            }
                            .controlSize(.small)

                            Button("Open System Settings → Accessibility") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(4)
                }
                .onAppear {
                    refreshDiagnostics()
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
