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

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
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
        return installEventTap()
    }

    func stop() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        window.removeAll(keepingCapacity: true)
        lastDirectionSign = 0
        onWiggleDetected = nil
    }

    func updateConfig(_ newConfig: Config) {
        self.config = newConfig
    }

    // ── Event tap setup ─────────────────────────────────────────────────

    private func installEventTap() -> Bool {
        // Sólo mouseMoved — los delta importantes vienen acá.
        // Usamos listenOnly para no consumir el evento (los clicks deben
        // seguir funcionando normal).
        let mask = (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let detector = Unmanaged<MagicSelectionDetector>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            detector.handleMouseEvent(event)
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            Self.logger.error("Failed to create CGEventTap for MagicSelectionDetector")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.eventTapRunLoopSource = source
        Self.logger.info("MagicSelectionDetector event tap installed")
        return true
    }

    // Para diagnosticar: cuenta eventos recibidos (sin log spam)
    private var eventCounter: Int = 0
    private var lastEventLogAt: TimeInterval = 0

    // ── Core: handle every mouseMoved event ─────────────────────────────

    private func handleMouseEvent(_ event: CGEvent) {
        let now = CACurrentMediaTime()
        let location = event.location // CGPoint en coords flipped (screen origin top-left)

        // Diagnóstico: cada 100 eventos, loguear señal de vida. Si nunca
        // se ve este log → el CGEventTap no está recibiendo eventos
        // (problema de permisos o tap roto).
        eventCounter += 1
        if eventCounter % 100 == 0 && (now - lastEventLogAt) > 2.0 {
            Self.logger.debug("Detector alive: \(self.eventCounter) mouse events processed")
            lastEventLogAt = now
        }

        // Calculamos deltaX manualmente porque event.getIntegerValueField(.mouseEventDeltaX)
        // a veces es 0 para eventos sintéticos.
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

    private func triggerWiggle(at flippedPoint: CGPoint, now: TimeInterval) {
        lastActivationAt = now
        window.removeAll(keepingCapacity: true)
        lastDirectionSign = 0

        // Convertimos de CGEvent coords (top-left origin) a NSEvent coords
        // (bottom-left origin) para que sea consistente con NSEvent.mouseLocation
        // que usa el resto del proyecto.
        let nsPoint = Self.convertToNSCoordinates(flippedPoint)

        Self.logger.info("Wiggle detected at \(String(format: "(%.0f, %.0f)", nsPoint.x, nsPoint.y))")

        // Llamamos en main para que el handler pueda crear UI sin race conditions
        DispatchQueue.main.async { [weak self] in
            self?.onWiggleDetected?(nsPoint)
        }
    }

    private static func convertToNSCoordinates(_ cgPoint: CGPoint) -> NSPoint {
        // El cursor en CGEvent viene en coords de la pantalla principal con
        // origen arriba-izquierda. NSScreen / NSEvent.mouseLocation usan
        // origen abajo-izquierda. Hay que invertir Y respecto a la altura
        // del bounding box de TODAS las pantallas combinadas.
        guard let primaryScreen = NSScreen.screens.first else {
            return NSPoint(x: cgPoint.x, y: cgPoint.y)
        }
        let flippedY = primaryScreen.frame.height - cgPoint.y
        return NSPoint(x: cgPoint.x, y: flippedY)
    }
}
