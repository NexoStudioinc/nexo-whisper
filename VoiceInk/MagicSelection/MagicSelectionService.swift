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

    // ── Dependencias del engine (inyectadas al boot) ────────────────────
    // Las usamos para el pipeline de valor (Tier 1): grabar el comando de
    // voz, transcribirlo con el modelo activo y transformar el texto con el
    // provider AI que el usuario ya tiene configurado.
    private weak var engine: VoiceInkEngine?

    /// Recorder dedicado para Magic Selection — independiente del recorder
    /// principal de la app para no pisar su estado de grabación.
    private let magicRecorder = Recorder()

    /// Overlay visual (glow del cursor + pill de estado).
    private let overlay = MagicModeOverlay()

    /// Panel flotante para respuestas (preguntas que NO reemplazan texto).
    private let answerPanel = MagicAnswerPanel()

    /// Monitor global de Esc para salir del modo.
    private var escMonitor: Any?

    /// Máquina de estados del MODO:
    /// - `off`: modo apagado, sin glow.
    /// - `ready`: modo activo (glow), sin grabar (transición).
    /// - `listening`: grabando el comando de voz.
    /// - `processing`: transcribiendo + IA + aplicando.
    /// El contexto (selección) se captura AL INICIO (cuando la selección está
    /// fresca) y se guarda acá, para no perderlo si algo la deselecciona.
    private enum ModeState {
        case off
        case ready
        case listening(context: MagicContext, audioURL: URL)
        case processing
    }
    private var modeState: ModeState = .off

    private var isModeOff: Bool {
        if case .off = modeState { return true }
        return false
    }

    /// Modo CONTINUO (wiggle + ⌥ Option): el glow queda siempre activo y el
    /// VAD corta cada comando por silencio, en loop, hasta salir. El modo
    /// NORMAL (wiggle solo) hace un comando y se apaga.
    private var isContinuous = false

    // VAD (corte por silencio) — solo en modo continuo.
    private var vadTimer: Timer?
    private var vadHasSpoken = false
    private var vadSilenceStart: Date?
    private var vadStartTime = Date()

    /// Llamar al boot (`VoiceInk.swift`) para inyectar el engine. Sin esto el
    /// trigger solo puede mostrar feedback, no completar el pipeline.
    func configure(engine: VoiceInkEngine) {
        self.engine = engine
        Self.logger.info("MagicSelectionService configured with engine")
    }

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
            // El modificador apretado durante el wiggle define el modo (ambos
            // configurables en Settings). Transcribe tiene prioridad si coincide.
            let flags = NSEvent.modifierFlags
            let mode: MagicTriggerMode
            if let rf = Self.modifierFlag(self.replaceDirectModifierName), flags.contains(rf) {
                mode = .replaceDirect
            } else if let tf = Self.modifierFlag(self.transcribeModifierName), flags.contains(tf) {
                mode = .transcribe
            } else if let cf = Self.modifierFlag(self.continuousModifierName), flags.contains(cf) {
                mode = .continuous
            } else {
                mode = .normal
            }
            Task { @MainActor in
                self.handleTrigger(at: location, source: .wiggle, mode: mode)
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

    /// Modo del trigger según el modificador apretado durante el wiggle.
    enum MagicTriggerMode {
        case normal        // wiggle solo → Magic (un comando por ciclo)
        case continuous    // modificador continuo → escucha en loop (VAD)
        case transcribe    // modificador transcribe → dictado puro (+mejora) y pega
        case replaceDirect // modificador reemplazo directo → pega sin abrir el panel
    }

    /// Mapea el nombre del modificador (Settings) a `NSEvent.ModifierFlags`.
    static func modifierFlag(_ name: String) -> NSEvent.ModifierFlags? {
        switch name {
        case "option": return .option
        case "control": return .control
        case "command": return .command
        case "shift": return .shift
        default: return nil
        }
    }

    var continuousModifierName: String {
        UserDefaults.standard.string(forKey: "magicSelection.continuousModifier") ?? "option"
    }
    var transcribeModifierName: String {
        UserDefaults.standard.string(forKey: "magicSelection.transcribeModifier") ?? "control"
    }
    var replaceDirectModifierName: String {
        UserDefaults.standard.string(forKey: "magicSelection.replaceDirectModifier") ?? "shift"
    }

    /// Modo dictado puro (transcribe + mejora si está activa, y pega). No Magic.
    private var isTranscribe = false
    /// Modo reemplazo directo: pega el resultado sin abrir el panel.
    private var isReplaceDirect = false

    private func handleTrigger(at location: NSPoint, source: TriggerSource, mode: MagicTriggerMode = .normal) {
        // Re-entrancy guard para el manejo síncrono del trigger.
        guard !isActivating else {
            Self.logger.debug("Already activating, ignoring trigger from \(source.rawValue)")
            return
        }
        isActivating = true
        defer { isActivating = false }

        Self.logger.info("🪄 Magic triggered by \(source.rawValue) mode=\(String(describing: mode)) at \(String(format: "(%.0f, %.0f)", location.x, location.y))")

        switch modeState {
        case .off:
            // Primer trigger: enciende el modo y arranca a escuchar.
            isContinuous = (mode == .continuous)
            isTranscribe = (mode == .transcribe)
            isReplaceDirect = (mode == .replaceDirect)
            activateMode()
            startListening()
        case .ready:
            startListening()
        case .listening(let context, let audioURL):
            if isContinuous {
                // En continuo el VAD corta cada comando; el trigger CIERRA el modo.
                exitMode()
            } else {
                // En normal el segundo wiggle corta y procesa el comando.
                finishListening(context: context, audioURL: audioURL)
            }
        case .processing:
            // En continuo, permitir cerrar aunque esté procesando.
            if isContinuous { exitMode() }
            else { Self.logger.info("Trigger ignorado: ya estoy procesando un comando") }
        }
    }

    // ── Encender / apagar el modo persistente ───────────────────────────

    private func activateMode() {
        overlay.show(state: .ready)
        installEscMonitor()
        showIntroIfNeeded()
        Self.logger.info("✨ Modo Magic ACTIVADO")
    }

    /// Muestra la explicación del flujo SOLO las primeras veces, para que el
    /// usuario entienda. Después el pill con waveform alcanza como indicador.
    private func showIntroIfNeeded() {
        let key = "magicSelection.introShownCount"
        let count = UserDefaults.standard.integer(forKey: key)
        guard count < 2 else { return }
        UserDefaults.standard.set(count + 1, forKey: key)
        NotificationManager.shared.showNotification(
            title: "🪄 Modo Magic. Seleccioná, dictá tu comando y hacé wiggle de nuevo para aplicar. Con ⌥+wiggle queda escuchando solo (corta por silencio). Esc para salir.",
            type: .info,
            duration: 9.0
        )
    }

    func exitMode() {
        endMagicMode(hideAnswer: true)
        Self.logger.info("✨ Modo Magic DESACTIVADO (wiggle/Esc)")
    }

    /// Apaga el glow y resetea el estado del modo. `hideAnswer=false` deja el
    /// panel de respuesta visible (cuando el comando fue una pregunta queremos
    /// que la respuesta quede en pantalla aunque el halo se apague).
    private func endMagicMode(hideAnswer: Bool) {
        stopVAD()
        if case .listening(_, let audioURL) = modeState {
            Task { @MainActor in
                await self.magicRecorder.stopRecording()
                self.cleanupTempFile(audioURL)
            }
        }
        modeState = .off
        isContinuous = false
        isTranscribe = false
        isReplaceDirect = false
        overlay.hide()
        if hideAnswer { answerPanel.hide() }
        removeEscMonitor()
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return } // 53 = Esc
            Task { @MainActor in self?.exitMode() }
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }

    // ── Paso 1: capturar selección (fresca) + arrancar grabación ────────
    // El contexto se captura ACÁ, no al corte: así la selección se guarda ni
    // bien hacés el wiggle, antes de que algo (foco, click) la deseleccione.
    // Clave para apps no nativas donde la selección se agarra por Cmd+C.
    private func startListening() {
        Task { @MainActor in
            let location = NSEvent.mouseLocation
            var context = MagicContextExtractor.extract(at: location)
            if context.bestText?.isEmpty ?? true {
                if let clip = await MagicContextExtractor.clipboardSelection() {
                    context.selectedText = clip
                }
            }
            // Si AX no marcó la selección como editable (típico cuando vino por
            // portapapeles: webs, Electron), lo confirmamos mirando si hay un
            // campo editable bajo el cursor. Así pega en inputs web/Electron.
            if !context.isSelectionEditable {
                context.isSelectionEditable = MagicContextExtractor.isEditableUnderCursor(at: location)
            }
            Self.logger.info("Context capturado al inicio: \(context.debugDescription) editable=\(context.isSelectionEditable)")

            // Pre-calentamiento oportunista: mientras el usuario dicta el
            // comando, adelantamos el arranque del motor de IA si conviene
            // (solo Local CLI; con API no hace nada). Esconde la latencia del
            // cold start detrás del tiempo de dictado. Sin costo constante.
            self.engine?.enhancementService?.prewarmForMagic()

            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("magic-\(UUID().uuidString).wav")

            do {
                try await self.magicRecorder.startRecording(toOutputFile: audioURL)
                self.modeState = .listening(context: context, audioURL: audioURL)
                self.overlay.update(state: .listening)
                // En modo continuo, el VAD corta el comando por silencio.
                if self.isContinuous { self.startVAD(audioURL: audioURL) }
                Self.logger.info("Grabando comando (continuous=\(self.isContinuous))")
            } catch {
                self.endMagicMode(hideAnswer: true)
                NotificationManager.shared.showNotification(
                    title: "🪄 No pude empezar a grabar. Revisá el permiso de micrófono.",
                    type: .error,
                    duration: 6.0
                )
                Self.logger.error("Falló startRecording: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // ── VAD: corte por silencio (modo continuo) ─────────────────────────
    private func startVAD(audioURL: URL) {
        vadHasSpoken = false
        vadSilenceStart = nil
        vadStartTime = Date()
        vadTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.vadTick(audioURL: audioURL) }
        }
        RunLoop.main.add(timer, forMode: .common)
        vadTimer = timer
    }

    private func stopVAD() {
        vadTimer?.invalidate()
        vadTimer = nil
    }

    private func vadTick(audioURL: URL) {
        // Si ya no estamos grabando este audio, frenar.
        guard case .listening(let context, let current) = modeState, current == audioURL else {
            stopVAD()
            return
        }

        let level = magicRecorder.audioMeter.averagePower  // 0–1 (normalizado)
        let elapsed = Date().timeIntervalSince(vadStartTime)

        // Grace period inicial: no cortar antes de que el usuario empiece.
        if elapsed < 0.6 { return }

        let voiceThreshold = 0.22
        let silenceThreshold = 0.14

        if level > voiceThreshold {
            vadHasSpoken = true
            vadSilenceStart = nil
        } else if level < silenceThreshold, vadHasSpoken {
            if vadSilenceStart == nil {
                vadSilenceStart = Date()
            } else if Date().timeIntervalSince(vadSilenceStart!) > 1.2 {
                // Fin del comando: silencio sostenido tras haber hablado.
                stopVAD()
                finishListening(context: context, audioURL: audioURL)
                return
            }
        }

        // Tope de seguridad: cortar a los 15s pase lo que pase.
        if elapsed > 15 {
            stopVAD()
            finishListening(context: context, audioURL: audioURL)
        }
    }

    // ── Paso 2: cortar → transcribir → IA → aplicar ─────────────────────
    // El `context` ya viene capturado desde startListening (selección fresca).
    private func finishListening(context: MagicContext, audioURL: URL) {
        stopVAD()
        modeState = .processing
        overlay.update(state: .thinking)

        Task { @MainActor in
            // Modo continuo: tras el comando, volver a escuchar (loop) salvo que
            // se haya cerrado el modo. Modo normal: apagar el halo.
            defer {
                if self.isContinuous {
                    if !self.isModeOff { self.startListening() }
                } else {
                    self.endMagicMode(hideAnswer: false)
                }
            }

            await self.magicRecorder.stopRecording()

            guard let engine = self.engine,
                  let model = engine.transcriptionModelManager.currentTranscriptionModel,
                  let enhancement = engine.enhancementService else {
                self.notifyError("Magic no está listo (modelo o IA sin configurar).")
                self.cleanupTempFile(audioURL)
                return
            }

            do {
                let command = try await engine.serviceRegistry.transcribe(audioURL: audioURL, model: model)
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.info("Comando transcripto: \(trimmedCommand, privacy: .public)")

                guard !trimmedCommand.isEmpty else {
                    // En continuo, un silencio sin comando es normal: no spamear.
                    if !self.isContinuous {
                        self.notifyError("No te escuché ningún comando. Probá de nuevo.")
                    }
                    self.cleanupTempFile(audioURL)
                    return
                }

                // MODO TRANSCRIPTOR: el dictado se transcribe, se mejora (si la
                // mejora de IA está activada) y se PEGA donde está el cursor.
                // No es Magic: no hay selección ni panel.
                if self.isTranscribe {
                    var output = trimmedCommand
                    if enhancement.isEnhancementEnabled {
                        if let enhanced = try? await enhancement.enhance(trimmedCommand) {
                            output = enhanced.0
                        }
                    }
                    CursorPaster.pasteReactivating(output, appPID: context.sourcePID)
                    Self.logger.info("Modo transcriptor → pegado (\(output.count) chars)")
                    self.cleanupTempFile(audioURL)
                    return
                }

                guard let selectedText = context.bestText, !selectedText.isEmpty else {
                    self.notifyError("No encontré texto seleccionado para aplicar el comando.")
                    self.cleanupTempFile(audioURL)
                    return
                }

                // Primer turno: streaming en vivo. Se AWAITea acá para que el
                // defer (apagar glow / re-escuchar en continuo) corra recién al
                // terminar el stream.
                await self.consumeStreamingTurn(
                    enhancement: enhancement,
                    selectedText: selectedText,
                    command: trimmedCommand,
                    context: context,
                    freshPanel: true
                )
            } catch {
                self.notifyError("No pude procesar el comando: \(error.localizedDescription)")
                Self.logger.error("Pipeline error: \(error.localizedDescription, privacy: .public)")
            }

            self.cleanupTempFile(audioURL)
        }
    }

    // ── Streaming: consume el stream y empuja tokens al panel ───────────
    /// Consume un turno de Magic en streaming. `freshPanel=true` es el primer
    /// comando (puede pegar directo si la selección es editable); `false` es una
    /// re-pregunta / botón desde el panel ya abierto (siempre muestra en panel).
    @MainActor
    private func consumeStreamingTurn(
        enhancement: AIEnhancementService,
        selectedText: String,
        command: String,
        context: MagicContext,
        freshPanel: Bool
    ) async {
        let history = freshPanel ? [] : (answerPanel.currentModel?.conversation ?? [])
        let events = enhancement.runMagicCommandStreaming(
            selectedText: selectedText,
            command: command,
            history: history
        )

        var model: MagicAnswerModel? = freshPanel ? nil : answerPanel.currentModel
        var pasteDirect = false
        var pendingAction: (tool: String, params: [String: String])? = nil
        var full = ""

        // Feedback inmediato cuando el panel ya está abierto (re-pregunta /
        // botón): mostramos "Pensando…" sin esperar a la respuesta. En modo
        // cliente (sin streaming) esto evita que parezca que no pasa nada.
        if !freshPanel { model?.beginThinking() }

        // Abre el panel (si hace falta) y arranca el turno visual.
        func openPanelIfNeeded(imageQuery: String?) {
            if freshPanel {
                let m = self.makeAnswerModel(selectedText: selectedText, context: context, enhancement: enhancement)
                model = m
                self.answerPanel.present(model: m, near: NSEvent.mouseLocation)
            }
            model?.beginTurn(imageQuery: imageQuery)
        }

        do {
            for try await event in events {
                switch event {
                case .control(let control):
                    // Modo REEMPLAZO DIRECTO: pega sí o sí, sin abrir el panel
                    // (modo "confío"), sea replace o answer.
                    if self.isReplaceDirect && freshPanel {
                        pasteDirect = true
                        break
                    }
                    switch control {
                    case .replace:
                        // Pegado directo solo en el primer turno con selección editable.
                        pasteDirect = freshPanel && context.isSelectionEditable
                        if !pasteDirect { openPanelIfNeeded(imageQuery: nil) }
                    case .answer(let imageQuery):
                        openPanelIfNeeded(imageQuery: imageQuery)
                    case .action(let tool, let params):
                        // El contenido se muestra en el panel y al cerrar el
                        // turno se ejecuta la acción (Notas / Mail / Recordatorio).
                        pendingAction = (tool, params)
                        openPanelIfNeeded(imageQuery: nil)
                    }
                case .token(let token):
                    full += token
                    if !pasteDirect {
                        model?.appendToken(token)
                        self.answerPanel.scheduleAutoHide()
                    }
                }
            }
            if pasteDirect {
                // force en reemplazo directo (pega aunque no detectemos editable).
                CursorPaster.pasteReactivating(full, appPID: context.sourcePID, force: self.isReplaceDirect)
                Self.logger.info("Streaming → pegado directo (\(full.count) chars, force=\(self.isReplaceDirect))")
            } else {
                model?.finishTurn(userCommand: command)
                if let action = pendingAction {
                    if MagicActionConfirmer.isEnabled {
                        // Mostrar el form de confirmación pre-cargado; al dar OK
                        // (con los datos eventualmente editados) se ejecuta.
                        MagicActionConfirmer.shared.confirm(tool: action.tool, params: action.params, content: full) { [weak self] t, p, c in
                            Task { @MainActor in await self?.runAction(tool: t, params: p, content: c) }
                        }
                    } else {
                        await self.runAction(tool: action.tool, params: action.params, content: full)
                    }
                }
                Self.logger.info("Streaming en panel completado (\(full.count) chars)")
            }
        } catch {
            if let model {
                model.failTurn("No pude completar: \(error.localizedDescription)")
            } else {
                self.notifyError("No pude procesar el comando: \(error.localizedDescription)")
            }
            Self.logger.error("Streaming error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Crea el modelo del panel con sus closures: re-pregunta (con historial) y
    /// "Reemplazar" (pega en el origen forzando, reactivando la app por PID).
    @MainActor
    private func makeAnswerModel(
        selectedText: String,
        context: MagicContext,
        enhancement: AIEnhancementService
    ) -> MagicAnswerModel {
        let m = MagicAnswerModel(selectedText: selectedText, historyStore: answerPanel.historyStore)
        let pid = context.sourcePID
        m.onReplace = { [weak self] in
            guard let self, let current = self.answerPanel.currentModel else { return }
            CursorPaster.pasteReactivating(current.responseText, appPID: pid, force: true)
            self.answerPanel.hide()
        }
        m.onCommand = { [weak self] cmd in
            guard let self else { return }
            Task { @MainActor in
                await self.consumeStreamingTurn(
                    enhancement: enhancement,
                    selectedText: selectedText,
                    command: cmd,
                    context: context,
                    freshPanel: false
                )
            }
        }
        return m
    }

    /// Ejecuta una acción de sistema (Notas / Mail / Recordatorio) con el
    /// contenido generado y avisa el resultado con un toast.
    @MainActor
    private func runAction(tool: String, params: [String: String], content: String) async {
        let outcome = await MagicActions.run(tool: tool, params: params, content: content)
        NotificationManager.shared.showNotification(
            title: "\(outcome.success ? "✅" : "⚠️") \(outcome.message)",
            type: outcome.success ? .info : .error,
            duration: 5.0
        )
        Self.logger.info("Acción \(tool, privacy: .public) → \(outcome.success ? "ok" : "fail")")
    }

    private func notifyError(_ message: String) {
        NotificationManager.shared.showNotification(
            title: "🪄 \(message)",
            type: .error,
            duration: 6.0
        )
    }

    private func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
