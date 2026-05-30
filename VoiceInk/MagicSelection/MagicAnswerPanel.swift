import AppKit
import SwiftUI
import OSLog

/// Resultado de un comando Magic, parseado del JSON que devuelve la IA (camino
/// NO-streaming / fallback). El camino de streaming usa el header de control
/// (`@@REPLACE@@` / `@@ANSWER@@`), ver `AIEnhancementService`.
struct MagicCommandResult {
    enum Action {
        /// Reemplazar la selección con `text`.
        case replace
        /// Mostrar `text` en el panel flotante, sin tocar el texto del usuario.
        case answer
    }

    let action: Action
    let text: String
    /// Término de entidad para buscar una imagen (solo en `answer`, opcional).
    let imageQuery: String?

    static func parse(_ raw: String) -> MagicCommandResult {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extraer el primer bloque {...} (tolerante a texto extra o backticks).
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start < end {
            let jsonSlice = String(cleaned[start...end])
            if let data = jsonSlice.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = obj["text"] as? String {
                let actionStr = (obj["action"] as? String)?.lowercased() ?? "replace"
                let action: Action = (actionStr == "answer") ? .answer : .replace
                let image = (obj["image"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return MagicCommandResult(
                    action: action,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    imageQuery: action == .answer ? image : nil
                )
            }
        }

        // Fallback: no vino JSON → tratamos todo como reemplazo.
        return MagicCommandResult(action: .replace, text: cleaned, imageQuery: nil)
    }
}

/// Acciones rápidas del panel (botones). Disparan un comando sin necesidad de
/// (Los chips de acción ahora son configurables: ver `MagicChip` /
/// `MagicChipStore` en MagicChips.swift — built-in + custom, on/off y orden
/// desde Settings.)

/// Busca la imagen (thumbnail) de una entidad en Wikipedia. Gratis, sin API
/// key. Prueba primero en español y cae a inglés.
enum MagicImageSearch {
    static func thumbnailURL(for query: String) async -> URL? {
        for lang in ["es", "en"] {
            if let url = await fetch(query: query, lang: lang) { return url }
        }
        return nil
    }

    private static func fetch(query: String, lang: String) async -> URL? {
        // Búsqueda (no título exacto) + pageimages en una sola query: maneja
        // "Messi" → encuentra "Lionel Messi" → devuelve su imagen.
        guard var comps = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php") else {
            return nil
        }
        comps.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "prop", value: "pageimages"),
            .init(name: "piprop", value: "thumbnail"),
            .init(name: "pithumbsize", value: "500"),
            .init(name: "generator", value: "search"),
            .init(name: "gsrsearch", value: query),
            .init(name: "gsrlimit", value: "1")
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryObj = json["query"] as? [String: Any],
              let pages = queryObj["pages"] as? [String: Any] else {
            return nil
        }
        // pages = { "<pageid>": { thumbnail: { source } } }
        for (_, value) in pages {
            if let page = value as? [String: Any],
               let thumb = page["thumbnail"] as? [String: Any],
               let src = thumb["source"] as? String,
               let u = URL(string: src) {
                return u
            }
        }
        return nil
    }
}

/// Historial observable (reactivo) de respuestas. Para reabrir lo que se generó
/// aunque se haya cerrado la ventana. (Conversación = ver MagicAnswerModel.)
@MainActor
final class MagicHistoryStore: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let text: String
        let imageQuery: String?
        let date: Date
        var preview: String {
            let t = text.replacingOccurrences(of: "\n", with: " ")
            return t.count > 48 ? String(t.prefix(48)) + "…" : t
        }
    }
    @Published private(set) var items: [Item] = []
    private let maxItems = 25

    func add(text: String, imageQuery: String?) {
        items.insert(Item(text: text, imageQuery: imageQuery, date: Date()), at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }
    }
    func clear() { items.removeAll() }
}

// ── Modelo reactivo del panel ────────────────────────────────────────────

/// Estado observable del panel de respuesta. El `MagicSelectionService`
/// consume el stream de la IA y empuja tokens acá; la vista los muestra en
/// vivo. También dispara nuevos comandos (re-pregunta / botones) vía closures.
@MainActor
final class MagicAnswerModel: ObservableObject {
    /// Texto de la respuesta actual (crece token a token en streaming).
    @Published var responseText: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorText: String? = nil
    @Published var imageURL: URL? = nil
    @Published var searchingImage: Bool = false
    /// Binding del campo de re-pregunta.
    @Published var question: String = ""
    /// True mientras hay una imagen para mostrar/buscar.
    @Published var hasImage: Bool = false

    /// Texto sobre el que opera la sesión (selección original).
    let selectedText: String

    /// Turnos previos (pregunta, respuesta) para dar contexto a las re-preguntas.
    private(set) var conversation: [(user: String, assistant: String)] = []
    private var currentImageQuery: String?

    /// Disparar un nuevo comando (re-pregunta del campo o botón preset).
    var onCommand: ((String) -> Void)?
    /// Pegar la respuesta actual en la app de origen (botón Reemplazar).
    var onReplace: (() -> Void)?
    /// Cerrar el panel.
    var onClose: (() -> Void)?

    /// True mientras esperamos la respuesta de un turno SIN haber recibido
    /// todavía el primer token. En este estado el texto VIEJO se mantiene
    /// visible (no parpadea a vacío) con el indicador "Pensando…". Se apaga al
    /// llegar el primer token (que recién ahí reemplaza el texto).
    @Published var isThinking: Bool = false

    /// Chip que disparó el turno en curso (para mostrar el spinner en SU chip).
    @Published var activeChipID: UUID? = nil

    /// Historial persistente de respuestas (menú reloj).
    let historyStore: MagicHistoryStore

    private var imageTask: Task<Void, Never>?

    // Undo/Redo: pila de versiones del texto. `versionIndex` apunta a la actual.
    private var versions: [String] = []
    private var versionIndex: Int = -1
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    init(selectedText: String, historyStore: MagicHistoryStore) {
        self.selectedText = selectedText
        self.historyStore = historyStore
    }

    // ── API que usa el service mientras consume el stream ──────────────

    /// Feedback INMEDIATO de "procesando": se llama apenas se dispara un
    /// comando (re-pregunta / botón), antes de esperar la respuesta. NO borra
    /// el texto: queda el anterior visible con el indicador "Pensando…" hasta
    /// que llega la respuesta nueva (clave en modo cliente, sin streaming).
    func beginThinking() {
        errorText = nil
        isStreaming = true
        isThinking = true
    }

    /// Arranca un turno nuevo. NO limpia el texto todavía (eso pasa al llegar el
    /// primer token); solo marca pensando y, si corresponde, busca imagen.
    func beginTurn(imageQuery: String?) {
        errorText = nil
        isStreaming = true
        isThinking = true
        currentImageQuery = imageQuery
        imageTask?.cancel()
        if let q = imageQuery {
            searchingImage = true
            imageTask = Task { @MainActor in
                let url = await MagicImageSearch.thumbnailURL(for: q)
                guard !Task.isCancelled else { return }
                self.imageURL = url
                self.searchingImage = false
                self.hasImage = (url != nil)
            }
        } else {
            searchingImage = false
        }
    }

    func appendToken(_ token: String) {
        // El primer token del turno reemplaza el texto viejo y limpia la imagen.
        if isThinking {
            isThinking = false
            responseText = ""
            imageURL = nil
            hasImage = (currentImageQuery != nil)
        }
        responseText += token
    }

    /// Cierra el turno: guarda en la conversación, el historial y el undo.
    func finishTurn(userCommand: String) {
        isStreaming = false
        isThinking = false
        activeChipID = nil
        let answer = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        conversation.append((userCommand, answer))
        historyStore.add(text: answer, imageQuery: currentImageQuery)
        pushVersion(answer)
    }

    func failTurn(_ message: String) {
        isStreaming = false
        isThinking = false
        activeChipID = nil
        errorText = message
    }

    // ── Undo / Redo del texto generado ─────────────────────────────────

    private func pushVersion(_ text: String) {
        // Si veníamos de un undo, descartamos el "futuro" antes de apilar.
        if versionIndex < versions.count - 1 {
            versions.removeSubrange((versionIndex + 1)...)
        }
        versions.append(text)
        versionIndex = versions.count - 1
        refreshUndoState()
    }

    func undo() {
        guard versionIndex > 0 else { return }
        versionIndex -= 1
        responseText = versions[versionIndex]
        refreshUndoState()
    }

    func redo() {
        guard versionIndex < versions.count - 1 else { return }
        versionIndex += 1
        responseText = versions[versionIndex]
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = versionIndex > 0
        canRedo = versionIndex < versions.count - 1
    }

    // ── API que usa la vista ───────────────────────────────────────────

    func submitQuestion() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }
        question = ""
        activeChipID = nil
        onCommand?(q)
    }

    /// Dispara un chip. Para "Traducir" arma el comando con el idioma destino
    /// (preferido / auto-detectado, o `overrideLanguage` si vino del submenú).
    func runChip(_ chip: MagicChip, overrideLanguage: String? = nil) {
        guard !isStreaming else { return }
        activeChipID = chip.id
        let cmd = chip.isTranslate
            ? MagicTranslation.command(for: selectedText, override: overrideLanguage)
            : chip.command
        onCommand?(cmd)
    }

    func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(responseText, forType: .string)
    }
}

// ── NSPanel que SÍ puede tomar foco (para el campo de re-pregunta) ───────

/// A diferencia de un `nonactivatingPanel` puro, este puede volverse key para
/// que el `TextField` de re-pregunta reciba el teclado. Idea de Hover
/// (FloatingPanel, GPL-3.0). Esc lo cierra.
final class MagicKeyPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Panel flotante que muestra la respuesta de Magic Selection al lado del
/// cursor. Reactivo (streaming), movible y redimensionable con el resize NATIVO
/// de macOS (cursores de doble flecha en bordes y esquinas), con foco para
/// re-preguntar.
@MainActor
final class MagicAnswerPanel {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicAnswerPanel"
    )

    private static let minCard = NSSize(width: 300, height: 220)
    private let defaultSize = NSSize(width: 400, height: 340)

    private var panel: MagicKeyPanel?
    private var autoHideTask: Task<Void, Never>?
    private(set) var currentModel: MagicAnswerModel?

    /// Historial persistente de respuestas (compartido entre sesiones).
    let historyStore = MagicHistoryStore()

    var isVisible: Bool { panel != nil }

    /// Muestra el panel para un modelo nuevo cerca de `anchor`.
    func present(model: MagicAnswerModel, near anchor: NSPoint) {
        currentModel = model
        model.onClose = { [weak self] in self?.hide() }

        buildPanel(model: model)
        positionPanel(near: anchor)
        panel?.orderFrontRegardless()
        panel?.makeKey()
        scheduleAutoHide()
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        panel?.orderOut(nil)
        panel = nil
        currentModel = nil
    }

    /// Reinicia el timer de auto-cierre. Por DEFAULT el panel NO se cierra solo
    /// (ya hay X y Esc para cerrarlo); se controla con la preferencia
    /// `magicSelection.panelAutoHideSeconds` (0 o ausente = nunca).
    func scheduleAutoHide() {
        autoHideTask?.cancel()
        let seconds = UserDefaults.standard.double(forKey: "magicSelection.panelAutoHideSeconds")
        guard seconds > 0 else { return }   // 0 / sin setear → no se cierra solo
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func buildPanel(model: MagicAnswerModel) {
        let size = defaultSize

        // Ventana `.titled` + `.resizable` + `.fullSizeContentView`: nos da el
        // RESIZE NATIVO de macOS (cursores de doble flecha en bordes y esquinas)
        // con la barra de título oculta y transparente. El contenido ocupa toda
        // la ventana. Se mueve con isMovableByWindowBackground (arrastrando el
        // interior); el resize lo maneja el sistema en los bordes (no compiten).
        let newPanel = MagicKeyPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.minSize = Self.minCard
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.standardWindowButton(.closeButton)?.isHidden = true
        newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newPanel.standardWindowButton(.zoomButton)?.isHidden = true
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        // Sombra/halo lo da SwiftUI (glow de color) en el margen transparente.
        newPanel.hasShadow = false
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        newPanel.hidesOnDeactivate = false
        newPanel.onCancel = { [weak self] in self?.hide() }

        let view = MagicAnswerView(
            model: model,
            onShare: { [weak self] in self?.presentShare() },
            onInteract: { [weak self] in self?.scheduleAutoHide() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        newPanel.contentView = hosting

        self.panel = newPanel
    }

    private func presentShare() {
        guard let panel, let hostingView = panel.contentView, let model = currentModel else { return }
        let picker = NSSharingServicePicker(items: [model.responseText])
        let bounds = hostingView.bounds
        let rect = NSRect(x: bounds.maxX - 60, y: bounds.maxY - 36, width: 1, height: 1)
        picker.show(relativeTo: rect, of: hostingView, preferredEdge: .maxY)
    }

    private func positionPanel(near anchor: NSPoint) {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchor.x + 18
        var y = anchor.y - size.height - 18
        if x + size.width > visible.maxX { x = anchor.x - size.width - 18 }
        if x < visible.minX { x = visible.minX + 8 }
        if y < visible.minY { y = anchor.y + 18 }
        if y + size.height > visible.maxY { y = visible.maxY - size.height - 8 }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}


// ── La tarjeta de respuesta ─────────────────────────────────────────────

private struct MagicAnswerView: View {
    @ObservedObject var model: MagicAnswerModel
    let onShare: () -> Void
    let onInteract: () -> Void

    @ObservedObject private var chipStore = MagicChipStore.shared
    @State private var copied = false

    private let violet = Color(red: 0.55, green: 0.36, blue: 0.96)
    private let cyan = Color(red: 0.36, green: 0.80, blue: 0.95)

    var body: some View {
        // Margen chico: el halo respira pero el borde de la card queda CERCA del
        // borde de la ventana, así el resize nativo (que agarra en el borde de la
        // ventana) es fácil de pescar y no se confunde con "mover".
        card
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            bodyScroll
            statusBar
            presetBar
            askBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.98))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.1
                )
        )
        // HALO que SIGUE la forma redondeada (no es un shadow de caja, así no se
        // ve cuadrado): un trazo gradient difuminado por detrás. Notorio en el
        // borde, se difumina suave hacia afuera y muere dentro del margen.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 3
                )
                .blur(radius: 6)
                .opacity(0.8)
        )
        // Sombra negra suave solo para despegar del fondo (sin color, sutil).
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }

    // ── Header ──────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [violet, cyan], startPoint: .leading, endPoint: .trailing))
            Text("Magic")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            if model.isStreaming {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            }

            Spacer()

            historyMenu
            iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copiar") {
                model.copyToPasteboard()
                withAnimation { copied = true }
                onInteract()
            }
            iconButton("square.and.arrow.up", help: "Compartir") { onShare(); onInteract() }
            iconButton("xmark", help: "Cerrar") { model.onClose?() }
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    // ── Cuerpo (texto en streaming + imagen + error) ────────────────────

    private var bodyScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let err = model.errorText {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.responseText.isEmpty && model.isThinking {
                    // Primer turno sin texto previo: "Pensando…" en el cuerpo.
                    HStack(spacing: 8) {
                        thinkingDots
                        Text("Pensando…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if !model.responseText.isEmpty {
                    // El texto se mantiene visible incluso mientras "Pensando…"
                    // (no parpadea a vacío); recién cambia al llegar el primer
                    // token del turno nuevo. Render Markdown (bloques de código
                    // con formato estilo chat de LLM).
                    MagicMarkdownView(text: model.responseText)
                }

                if model.searchingImage {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.05))
                        .frame(height: 120)
                        .overlay(ProgressView().controlSize(.small))
                } else if let imageURL = model.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        case .empty:
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white.opacity(0.05))
                                .frame(height: 130)
                                .overlay(ProgressView().controlSize(.small))
                        default:
                            EmptyView()
                        }
                    }
                }

                // Reemplazar al final de la respuesta lista: discreto, alineado
                // a la izquierda (no invasivo).
                if model.onReplace != nil, !model.isStreaming, !model.responseText.isEmpty {
                    Button { model.onReplace?(); onInteract() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc").font(.system(size: 10, weight: .semibold))
                            Text("Reemplazar texto").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(violet)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            Capsule().fill(violet.opacity(0.12))
                                .overlay(Capsule().strokeBorder(violet.opacity(0.45), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .help("Reemplazar / Pegar en el origen")
                }
            }
            .padding(14)
        }
    }

    // ── Barra de estado "Pensando…" (cuando ya hay texto viejo visible) ─

    @ViewBuilder private var statusBar: some View {
        if model.isThinking && !model.responseText.isEmpty {
            HStack(spacing: 8) {
                thinkingDots
                Text("Pensando…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.06)), alignment: .top)
        }
    }

    // ── Barra de chips de acción (configurables desde Settings) ─────────

    @ViewBuilder private var presetBar: some View {
        let chips = chipStore.enabledChips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        if chip.isTranslate {
                            translateChip(chip)
                        } else {
                            Button {
                                model.runChip(chip); onInteract()
                            } label: { chipLabel(chip) }
                            .buttonStyle(.plain)
                            .disabled(model.isStreaming)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
            }
        }
    }

    /// Chip "Traducir" con DOS zonas en la misma cápsula (no aparece
    /// desactivado): tocás el GLOBO → menú de idiomas; tocás el TEXTO → traduce
    /// al destino resuelto (preferido / auto-detectado).
    private func translateChip(_ chip: MagicChip) -> some View {
        let isActive = model.activeChipID == chip.id && model.isStreaming
        let tint = Color.white.opacity(model.isStreaming && !isActive ? 0.4 : 0.85)
        return HStack(spacing: 5) {
            // Globo → menú de idiomas.
            Menu {
                ForEach(MagicTranslation.languages, id: \.self) { lang in
                    Button(lang) { model.runChip(chip, overrideLanguage: lang); onInteract() }
                }
            } label: {
                if isActive {
                    ProgressView().controlSize(.mini).scaleEffect(0.55).frame(width: 10, height: 10)
                } else {
                    Image(systemName: chip.systemImage).font(.system(size: 9, weight: .semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: isActive ? 12 : 12)

            // Texto → traduce.
            Button { model.runChip(chip); onInteract() } label: {
                Text(chip.title).font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            Capsule().fill(isActive ? AnyShapeStyle(LinearGradient(colors: [violet.opacity(0.4), cyan.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
        )
        .disabled(model.isStreaming)
    }

    private func chipLabel(_ chip: MagicChip) -> some View {
        let isActive = model.activeChipID == chip.id && model.isStreaming
        return HStack(spacing: 4) {
            if isActive {
                ProgressView().controlSize(.mini).scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: chip.systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(chip.title).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(model.isStreaming && !isActive ? 0.4 : 0.85))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            Capsule().fill(isActive ? AnyShapeStyle(LinearGradient(colors: [violet.opacity(0.4), cyan.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
        )
    }

    // ── Footer: undo/redo + campo de re-pregunta inline ─────────────────

    private var askBar: some View {
        HStack(spacing: 8) {
            // Undo / Redo del texto generado (acá, no en el header lleno).
            footerIcon("arrow.uturn.backward", help: "Deshacer", enabled: model.canUndo) {
                model.undo(); onInteract()
            }
            footerIcon("arrow.uturn.forward", help: "Rehacer", enabled: model.canRedo) {
                model.redo(); onInteract()
            }
            Divider().frame(height: 16).overlay(Color.white.opacity(0.12))

            TextField("Seguí preguntando…", text: $model.question)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.92))
                .onSubmit { model.submitQuestion(); onInteract() }
            Button {
                model.submitQuestion(); onInteract()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        (model.question.isEmpty || model.isStreaming)
                            ? AnyShapeStyle(.white.opacity(0.25))
                            : AnyShapeStyle(LinearGradient(colors: [violet, cyan], startPoint: .leading, endPoint: .trailing))
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.question.isEmpty || model.isStreaming)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.03))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.06)), alignment: .top)
    }

    private func footerIcon(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.2))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    // ── Sub-componentes ─────────────────────────────────────────────────

    private var historyMenu: some View {
        Menu {
            if model.historyStore.items.isEmpty {
                Text("Sin historial")
            } else {
                ForEach(model.historyStore.items) { item in
                    Button(item.preview) {
                        model.responseText = item.text
                    }
                }
                Divider()
                Button("Limpiar historial", role: .destructive) { model.historyStore.clear() }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 22, height: 22)
                .background(circleBg)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Historial")
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 22, height: 22)
                .background(circleBg)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// 3 puntitos que laten (indicador de "pensando" con el color de la marca).
    private var thinkingDots: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(LinearGradient(colors: [violet, cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * abs(sin(t * 3 + Double(i) * 0.7)))
                }
            }
        }
    }

    private var circleBg: some View {
        Circle()
            .fill(.white.opacity(0.07))
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [violet.opacity(0.7), cyan.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
            )
    }
}
