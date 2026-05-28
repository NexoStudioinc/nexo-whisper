import AppKit
import Foundation
import OSLog

/// Orquestador del flujo Magic Selection. Singleton para que la app entera
/// pueda activarlo desde cualquier callback (gesto del mouse, hotkey,
/// menubar item).
///
/// **Estado F1** (esta versión): detecta el trigger, captura contexto,
/// loguea a Console. Sin UI ni integración con recorder todavía.
///
/// Próximas fases:
/// - F2: abrir `CursorGlowPanel` + `MagicSelectionPillView` al activarse.
/// - F3: disparar el pipeline de grabación (VoiceInkEngine.toggleRecord)
///   con un flag especial para que el resultado se inyecte como
///   "transformación del contexto" en lugar de un paste normal.
/// - F4: prompt templates configurables ("traducir", "formalizar",
///   "convertir en bullets") + AI provider gating (Pro).
@MainActor
final class MagicSelectionService {

    static let shared = MagicSelectionService()

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicSelectionService"
    )

    // ── Persistencia de config (UserDefaults) ───────────────────────────

    private enum DefaultsKeys {
        static let enabled = "magicSelection.enabled"
        static let wiggleEnabled = "magicSelection.wiggleEnabled"
        static let windowDurationMs = "magicSelection.windowDurationMs"
        static let directionChangesThreshold = "magicSelection.directionChangesThreshold"
        static let minVelocityPxPerSec = "magicSelection.minVelocityPxPerSec"
        static let cooldownSec = "magicSelection.cooldownSec"
    }

    /// Master switch del feature.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKeys.enabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKeys.enabled)
            if newValue {
                startIfNeeded()
            } else {
                stop()
            }
        }
    }

    /// Si está apagado, solo el hotkey activa Magic Selection (no el wiggle).
    var isWiggleEnabled: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKeys.wiggleEnabled) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKeys.wiggleEnabled)
            // Reinicia el detector con la nueva config
            stop()
            startIfNeeded()
        }
    }

    /// Construye un `Config` del detector leyendo Settings.
    private var detectorConfig: MagicSelectionDetector.Config {
        var cfg = MagicSelectionDetector.Config.default
        let defs = UserDefaults.standard
        if let v = defs.object(forKey: DefaultsKeys.windowDurationMs) as? Int { cfg.windowDurationMs = v }
        if let v = defs.object(forKey: DefaultsKeys.directionChangesThreshold) as? Int { cfg.directionChangesThreshold = v }
        if let v = defs.object(forKey: DefaultsKeys.minVelocityPxPerSec) as? Double { cfg.minVelocityPxPerSec = CGFloat(v) }
        if let v = defs.object(forKey: DefaultsKeys.cooldownSec) as? Double { cfg.cooldownSec = v }
        return cfg
    }

    // ── Estado interno ─────────────────────────────────────────────────

    private var detector: MagicSelectionDetector?
    private var isActivating = false

    /// Estado público del detector para diagnóstico en Settings.
    enum DetectorStatus {
        case notStarted
        case running
        case startFailed(reason: String)
        case disabledByUser
    }

    private(set) var detectorStatus: DetectorStatus = .notStarted

    private init() {
        Self.logger.info("MagicSelectionService initialized")
    }

    /// Llamar al boot de la app (`VoiceInk.swift`). Si el feature está
    /// activado y el wiggle también, monta el detector. Si está apagado,
    /// no hace nada (el hotkey igual sigue funcionando porque va por
    /// `ShortcutAction`).
    func startIfNeeded() {
        Self.logger.info("🔧 startIfNeeded called — isEnabled=\(self.isEnabled, privacy: .public), isWiggleEnabled=\(self.isWiggleEnabled, privacy: .public)")

        guard isEnabled else {
            Self.logger.info("Magic Selection disabled by user — not starting detector")
            detectorStatus = .disabledByUser
            return
        }
        guard isWiggleEnabled else {
            Self.logger.info("Magic Selection wiggle disabled — hotkey still active via ShortcutAction")
            detectorStatus = .disabledByUser
            return
        }
        guard detector == nil else {
            Self.logger.debug("Detector already running")
            detectorStatus = .running
            return
        }

        // Verificar Accessibility ANTES de intentar el event tap.
        if !AXIsProcessTrusted() {
            let msg = "AX permission missing — go to System Settings → Privacy & Security → Accessibility → enable 'Nexo Whisper Magic'"
            Self.logger.error("\(msg, privacy: .public)")
            detectorStatus = .startFailed(reason: msg)
            return
        }

        let det = MagicSelectionDetector(config: detectorConfig)
        let ok = det.start { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                self.handleTrigger(at: location, source: .wiggle)
            }
        }
        if ok {
            detector = det
            detectorStatus = .running
            Self.logger.info("✅ Magic Selection detector started (wiggle enabled)")
        } else {
            detectorStatus = .startFailed(reason: "CGEventTap installation failed — needs Input Monitoring permission")
            Self.logger.error("❌ Failed to start Magic Selection detector — likely missing Input Monitoring permission")
        }
    }

    func stop() {
        detector?.stop()
        detector = nil
        detectorStatus = .notStarted
        Self.logger.info("Magic Selection detector stopped")
    }

    /// Llamar este método desde el `ShortcutAction.magicSelection` handler
    /// para activar el flow vía hotkey en lugar de wiggle.
    func triggerFromHotkey() {
        Self.logger.info("🔥 triggerFromHotkey called — hotkey received by service")
        let location = NSEvent.mouseLocation
        handleTrigger(at: location, source: .hotkey)
    }

    /// Trigger manual desde Settings → "Force trigger now".
    /// Útil para confirmar que el pipeline completo (extractor + service) funciona
    /// sin depender del detector ni del shortcut monitor.
    func triggerManually() {
        Self.logger.info("🧪 Manual trigger from Settings")
        let location = NSEvent.mouseLocation
        handleTrigger(at: location, source: .hotkey)
    }

    // ── Trigger handling ────────────────────────────────────────────────

    enum TriggerSource: String {
        case wiggle
        case hotkey
    }

    private func handleTrigger(at location: NSPoint, source: TriggerSource) {
        // Re-entrancy guard
        guard !isActivating else {
            Self.logger.debug("Already activating, ignoring trigger from \(source.rawValue)")
            return
        }
        isActivating = true
        defer { isActivating = false }

        Self.logger.info("🪄 Magic Selection triggered by \(source.rawValue) at \(String(format: "(%.0f, %.0f)", location.x, location.y))")

        // Capturar contexto (técnica AX del otro agente)
        let context = MagicContextExtractor.extract(at: location)

        // F1: solo loguear. Sin UI ni grabación todavía.
        Self.logger.info("Context: \(context.debugDescription)")
        if let text = context.bestText {
            Self.logger.info("Best text under cursor:\n\(text.prefix(200))")
        } else {
            Self.logger.info("No text could be extracted under cursor")
        }

        // F2+: TODO — abrir UI y arrancar recording
        // CursorGlowPanel.shared.show(at: location)
        // MagicSelectionPillView.show(at: location)
        // engine.toggleRecord(... withMagicContext: context)
    }
}
