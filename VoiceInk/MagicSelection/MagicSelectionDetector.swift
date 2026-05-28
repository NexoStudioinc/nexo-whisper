import AppKit
import CoreGraphics
import Foundation
import OSLog

/// Detecta el gesto "wiggle" del mouse (vaivén rápido horizontal) usando un
/// `CGEventTap` global. Sigue el mismo patrón que `ShortcutMonitor` para
/// mantener consistencia con el resto del proyecto.
///
/// Algoritmo:
/// - Mantiene una ventana deslizante de los últimos eventos `mouseMoved`.
/// - Cada evento aporta su delta X (signo + magnitud) y timestamp.
/// - Detecta cuántos cambios de dirección horizontal ocurrieron dentro de la
///   ventana de tiempo (`windowDurationMs`).
/// - Si supera el umbral (`directionChangesThreshold`) **y** la velocidad
///   promedio supera `minVelocityPxPerSec`, dispara el callback.
/// - Cooldown de `cooldownSec` segundos para evitar disparos en cascada.
///
/// Pensado para correr siempre que el usuario tenga el feature Magic
/// Selection activado en Settings. Cuando se apaga, se libera el event tap.
///
/// **Permisos**: requiere Accessibility (la app ya lo pide para el recorder).
final class MagicSelectionDetector {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicSelectionDetector"
    )

    // ── Config ajustable desde Settings ─────────────────────────────────
    struct Config {
        /// Ventana de tiempo en la que se cuentan los cambios de dirección.
        var windowDurationMs: Int = 400
        /// Cuántos cambios de dirección (sign flips) hacen falta para disparar.
        var directionChangesThreshold: Int = 5
        /// Velocidad promedio mínima del movimiento, en px/s. Filtra wiggles
        /// lentos involuntarios.
        var minVelocityPxPerSec: CGFloat = 250
        /// Magnitud mínima de cada delta para ser considerado (filtra jitter
        /// del trackpad o vibración).
        var minMovementPx: CGFloat = 4
        /// Tiempo sin disparar después de una activación exitosa.
        var cooldownSec: TimeInterval = 2.0

        static let `default` = Config()
    }

    // ── Estado interno ─────────────────────────────────────────────────
    private struct MovementEvent {
        let timestamp: TimeInterval  // CACurrentMediaTime()
        let deltaX: CGFloat
    }

    private var config: Config
    private var window: [MovementEvent] = []
    private var lastDirectionSign: Int = 0  // -1 izquierda, 0 idle, 1 derecha
    private var lastActivationAt: TimeInterval = 0
    private var lastMouseLocation: NSPoint = .zero

    private var eventMonitor: Any?
    private var onWiggleDetected: ((NSPoint) -> Void)?

    init(config: Config = .default) {
        self.config = config
    }

    deinit {
        stop()
    }

    /// Empieza a monitorear. Llama el callback cuando detecta un wiggle.
    /// El point pasado es la posición global del cursor al momento del trigger.
    @discardableResult
    func start(onWiggleDetected: @escaping (NSPoint) -> Void) -> Bool {
        stop()
        self.onWiggleDetected = onWiggleDetected
        return installEventMonitor()
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
        window.removeAll(keepingCapacity: true)
        lastDirectionSign = 0
        onWiggleDetected = nil
    }

    func updateConfig(_ newConfig: Config) {
        self.config = newConfig
    }

    // ── Event monitor setup ─────────────────────────────────────────────

    private func installEventMonitor() -> Bool {
        // Usamos NSEvent.addGlobalMonitorForEvents en vez de CGEventTap.
        // Razones:
        //   - No requiere Input Monitoring permission separado de Accessibility
        //   - No tiene side-effects sobre el rendering del cursor (CGEventTap
        //     puede causar que el cursor desaparezca en algunas situaciones)
        //   - API más simple, menos puntos de falla
        //   - Para wiggle detection, los ~10-20ms de latencia adicional de
        //     NSEvent vs CGEventTap no afectan en absoluto
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.handleNSEvent(event)
        }

        if eventMonitor == nil {
            Self.logger.error("Failed to install NSEvent global monitor for MagicSelectionDetector")
            return false
        }

        Self.logger.info("MagicSelectionDetector NSEvent monitor installed")
        return true
    }

    private func handleNSEvent(_ event: NSEvent) {
        // NSEvent.locationInWindow para mouse global no aplica — usamos
        // mouseLocation que ya está en coords de pantalla.
        let location = NSEvent.mouseLocation
        let cgPoint = CGPoint(x: location.x, y: location.y)
        // Llamamos al mismo path que el viejo callback CGEvent
        handleMovementUpdate(at: cgPoint)
    }

    // Para diagnosticar: cuenta eventos recibidos (sin log spam)
    private var eventCounter: Int = 0
    private var lastEventLogAt: TimeInterval = 0

    // ── Core: handle every mouseMoved event ─────────────────────────────

    /// Procesa un movimiento del mouse. Llamado tanto por el detector
    /// NSEvent como (en F2) potencialmente por test programático.
    private func handleMovementUpdate(at location: CGPoint) {
        let now = CACurrentMediaTime()

        // Diagnóstico: cada 100 eventos, loguear señal de vida.
        eventCounter += 1
        if eventCounter % 100 == 0 && (now - lastEventLogAt) > 2.0 {
            Self.logger.debug("Detector alive: \(self.eventCounter) mouse events processed")
            lastEventLogAt = now
        }

        let deltaX = location.x - lastMouseLocation.x
        lastMouseLocation = NSPoint(x: location.x, y: location.y)

        // Skip si el movimiento es demasiado chico (jitter)
        guard abs(deltaX) >= config.minMovementPx else { return }

        // Cooldown
        let timeSinceLastActivation = now - lastActivationAt
        if lastActivationAt > 0 && timeSinceLastActivation < config.cooldownSec {
            return
        }

        // Agregar al sliding window
        window.append(MovementEvent(timestamp: now, deltaX: deltaX))

        // Drop eventos viejos fuera de la ventana
        let windowCutoff = now - (Double(config.windowDurationMs) / 1000.0)
        while let first = window.first, first.timestamp < windowCutoff {
            window.removeFirst()
        }

        // Necesitamos al menos algunos eventos para evaluar
        guard window.count >= config.directionChangesThreshold else { return }

        // Contar cambios de signo
        var directionChanges = 0
        var prevSign = 0
        for ev in window {
            let sign = ev.deltaX > 0 ? 1 : -1
            if prevSign != 0 && sign != prevSign {
                directionChanges += 1
            }
            prevSign = sign
        }

        guard directionChanges >= config.directionChangesThreshold else { return }

        // Calcular velocidad promedio (px/s)
        let totalDistance = window.reduce(0.0) { $0 + abs($1.deltaX) }
        let elapsedSec = window.last!.timestamp - window.first!.timestamp
        guard elapsedSec > 0 else { return }
        let avgVelocity = totalDistance / CGFloat(elapsedSec)

        // Diagnóstico: si llegamos hasta acá pero falla velocity, logear
        // para que el user pueda ajustar el threshold en Settings.
        if avgVelocity < config.minVelocityPxPerSec {
            Self.logger.debug("Wiggle near-miss: \(directionChanges) direction changes detected, but velocity \(Int(avgVelocity)) px/s < threshold \(Int(self.config.minVelocityPxPerSec)) px/s")
            return
        }

        // 🎯 ¡Wiggle detectado!
        triggerWiggle(at: location, now: now)
    }

    private func triggerWiggle(at point: CGPoint, now: TimeInterval) {
        lastActivationAt = now
        window.removeAll(keepingCapacity: true)
        lastDirectionSign = 0

        // Con NSEvent.mouseLocation las coords ya están en sistema NSScreen
        // (origen abajo-izquierda), no hace falta convertir.
        let nsPoint = NSPoint(x: point.x, y: point.y)

        Self.logger.info("Wiggle detected at \(String(format: "(%.0f, %.0f)", nsPoint.x, nsPoint.y))")

        // El handler se llama desde main (el callback de NSEvent ya viene de main)
        onWiggleDetected?(nsPoint)
    }
}
