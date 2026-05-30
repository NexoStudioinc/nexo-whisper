import AppKit
import SwiftUI
import OSLog

/// Estado visual del modo Magic. Maneja qué muestra el glow + el pill.
enum MagicVisualState: Equatable {
    /// Modo apagado — overlay oculto.
    case off
    /// Modo activo, esperando que el usuario toque para hablar.
    case ready
    /// Grabando el comando de voz del usuario.
    case listening
    /// Procesando (transcripción + IA + reemplazo).
    case thinking

    var pillText: String {
        switch self {
        case .off: return ""
        case .ready: return "Modo Magic · tocá para hablar · Esc para salir"
        case .listening: return "Escuchando tu comando…"
        case .thinking: return "Pensando…"
        }
    }
}

/// Overlay flotante que dibuja un aura (glow) violeta→cyan alrededor del
/// cursor + un pill con el estado, mientras el modo Magic está activo.
///
/// Usa un `NSPanel` transparente, sin foco, que ignora el mouse (los clicks
/// pasan de largo hacia la app de abajo) y sigue al cursor en tiempo real
/// mediante un monitor global de movimiento del mouse.
@MainActor
final class MagicModeOverlay {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicModeOverlay"
    )

    /// Tamaño del panel. El cursor queda en el centro; el glow rodea al
    /// cursor y el pill flota debajo. Chico a propósito: cuanto menos área hay
    /// que recomponer/mover cada frame, más pegado va el glow al cursor.
    private static let panelSize = NSSize(width: 200, height: 200)

    private var panel: NSPanel?
    private var trackTimer: Timer?
    private let stateModel = MagicOverlayStateModel()

    func show(state: MagicVisualState) {
        stateModel.showLabels = UserDefaults.standard.integer(forKey: "magicSelection.introShownCount") <= 2
        stateModel.state = state
        if panel == nil {
            buildPanel()
            startTrackingCursor()
        }
        repositionAtCursor()
        panel?.orderFrontRegardless()
    }

    func update(state: MagicVisualState) {
        stateModel.state = state
    }

    func hide() {
        stateModel.state = .off
        stopTrackingCursor()
        panel?.orderOut(nil)
        panel = nil
    }

    // ── Construcción del panel ──────────────────────────────────────────

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: MagicGlowView(model: stateModel))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hosting

        self.panel = panel
        Self.logger.info("Magic overlay panel construido")
    }

    // ── Seguimiento del cursor ──────────────────────────────────────────

    /// Seguimos el cursor con un timer de alta frecuencia en `.common` run
    /// loop mode (no por eventos de mouse). Así el glow va pegado SIEMPRE —
    /// incluso cuando nuestra app está al frente o no llegan eventos globales
    /// (lo que hacía que el halo "se quedara fijo"). Lee `mouseLocation` cada
    /// frame, sin depender de que el sistema nos mande movimientos.
    private func startTrackingCursor() {
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionAtCursor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackTimer = timer
    }

    private func stopTrackingCursor() {
        trackTimer?.invalidate()
        trackTimer = nil
    }

    /// Centra el panel en el cursor. `NSEvent.mouseLocation` y el origin del
    /// panel comparten coords de pantalla (origen abajo-izquierda), así que
    /// no hace falta flippear Y.
    private func repositionAtCursor() {
        guard let panel else { return }
        let cursor = NSEvent.mouseLocation
        let origin = NSPoint(
            x: cursor.x - Self.panelSize.width / 2,
            y: cursor.y - Self.panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

/// Modelo observable que el SwiftUI view escucha para animar transiciones.
@MainActor
final class MagicOverlayStateModel: ObservableObject {
    @Published var state: MagicVisualState = .off
    /// Solo las primeras veces mostramos texto ("Escuchando…") junto al
    /// waveform. Después alcanza el waveform encapsulado.
    @Published var showLabels: Bool = false
}

// ── La vista del glow + pill ────────────────────────────────────────────

private struct MagicGlowView: View {
    @ObservedObject var model: MagicOverlayStateModel
    @State private var pulse = false

    // Paleta Nexo: violeta → cyan.
    private let violet = Color(red: 0.55, green: 0.36, blue: 0.96)
    private let cyan = Color(red: 0.36, green: 0.80, blue: 0.95)

    var body: some View {
        ZStack {
            glow
            pill
                .offset(y: 58)
        }
        .frame(width: 200, height: 200)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // Aura radial difusa alrededor del cursor — SIN anillo, solo el glow.
    // Más intenso y con radio más chico para que se note en cualquier fondo:
    // un núcleo violeta brillante + un halo cyan exterior, ambos difuminados.
    private var glow: some View {
        let intensity: CGFloat = {
            switch model.state {
            case .listening: return 1.0
            case .thinking: return 0.9
            case .ready: return 0.78
            case .off: return 0.0
            }
        }()

        return ZStack {
            // Halo exterior cyan (difuso, da el "aura").
            Circle()
                .fill(
                    RadialGradient(
                        colors: [cyan.opacity(0.55 * intensity), .clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: 52
                    )
                )
                .frame(width: 110, height: 110)
                .blur(radius: 8)

            // Núcleo violeta intenso (se nota incluso en fondos claros/oscuros).
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            violet.opacity(0.95 * intensity),
                            violet.opacity(0.55 * intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 28
                    )
                )
                .frame(width: 64, height: 64)
                .blur(radius: 5)
        }
        .scaleEffect(pulseScale)
        .animation(.easeInOut(duration: 0.3), value: model.state)
    }

    private var pulseScale: CGFloat {
        guard model.state == .listening else { return 1.0 }
        return pulse ? 1.2 : 0.85
    }

    // Pill chiquito al lado del cursor — SOLO durante listening/thinking.
    // En `ready` no se muestra: el halo ya indica que el modo está activo.
    private var pill: some View {
        Group {
            if model.state == .listening || model.state == .thinking {
                HStack(spacing: 7) {
                    indicator
                    // "Escuchando" NO se muestra (solo el waveform). "Pensando" sí.
                    if !shortLabel.isEmpty {
                        Text(shortLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.80))
                        .overlay(
                            Capsule().strokeBorder(
                                LinearGradient(colors: [violet, cyan], startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                        )
                )
                .shadow(color: violet.opacity(0.5), radius: 8)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.state)
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.state {
        case .thinking:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        default:
            MagicWaveformView(color: cyan)
        }
    }

    private var shortLabel: String {
        switch model.state {
        case .thinking: return "Pensando…"
        default: return ""   // listening: solo el waveform, sin texto
        }
    }
}

/// Waveform animado (barritas que suben y bajan) para indicar escucha.
private struct MagicWaveformView: View {
    let color: Color
    @State private var animating = false
    private let bars = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: animating ? 13 : 4)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.09),
                        value: animating
                    )
            }
        }
        .frame(height: 14)
        .onAppear { animating = true }
    }
}
