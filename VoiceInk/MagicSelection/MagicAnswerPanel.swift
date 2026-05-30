import AppKit
import SwiftUI
import OSLog

/// Resultado de un comando Magic, parseado del JSON que devuelve la IA.
/// La IA decide si transforma el texto (`replace`) o responde una pregunta
/// (`answer`). Si el modelo no devuelve JSON válido, asumimos `replace` con
/// el texto crudo (comportamiento por defecto, no rompe el flujo).
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

/// Panel flotante que muestra una respuesta de Magic Selection al lado del
/// cursor, sin tocar el texto del usuario (para preguntas tipo "qué significa
/// esto", "dame sinónimos", "qué es esto").
///
/// Mismo molde que `MagicModeOverlay`: NSPanel transparente, sin foco. A
/// diferencia del glow, este SÍ recibe clicks (para poder cerrarlo / scrollear).
@MainActor
final class MagicAnswerPanel {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicAnswerPanel"
    )

    // Margen transparente (20px por lado) alrededor de la card para que la
    // sombra respire. El tamaño se calcula según el contenido (más grande para
    // respuestas largas / código).
    private static let margin: CGFloat = 20
    private var currentPanelSize = NSSize(width: 400, height: 320)

    private var panel: NSPanel?
    private var escMonitor: Any?
    private var autoHideTask: Task<Void, Never>?
    private var hostingView: NSView?
    private var currentText: String = ""
    private var lastAnchor: NSPoint = .zero

    /// Item del historial de respuestas (por si se cierra la ventana y quedó
    /// algo sin copiar). Vive en memoria; se puede limpiar.
    struct HistoryItem: Identifiable {
        let id = UUID()
        let text: String
        let imageQuery: String?
        let date: Date
        var preview: String {
            let t = text.replacingOccurrences(of: "\n", with: " ")
            return t.count > 48 ? String(t.prefix(48)) + "…" : t
        }
    }
    private var history: [HistoryItem] = []
    private let maxHistory = 25

    /// Muestra la respuesta cerca de `anchor` y la guarda en el historial.
    func show(text: String, imageQuery: String? = nil, near anchor: NSPoint) {
        history.insert(HistoryItem(text: text, imageQuery: imageQuery, date: Date()), at: 0)
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        showInternal(text: text, imageQuery: imageQuery, near: anchor)
    }

    /// Muestra sin agregar al historial (usado al reabrir desde el historial).
    private func showInternal(text: String, imageQuery: String?, near anchor: NSPoint) {
        lastAnchor = anchor
        buildPanelIfNeeded(text: text, imageQuery: imageQuery)
        positionPanel(near: anchor)
        panel?.orderFrontRegardless()
        installEscMonitor()

        // Auto-cierre por inactividad (generoso: el usuario puede leer).
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        removeEscMonitor()
        panel?.orderOut(nil)
        panel = nil
    }

    private func buildPanelIfNeeded(text: String, imageQuery: String?) {
        // Reconstruimos siempre para refrescar el contenido.
        panel?.orderOut(nil)

        // Tamaño según contenido: más grande para respuestas largas / código.
        let lineCount = text.components(separatedBy: "\n").count
        let isLong = text.count > 520 || lineCount > 12
        let cardSize = isLong ? NSSize(width: 470, height: 440)
                              : NSSize(width: 360, height: 300)
        let panelSize = NSSize(width: cardSize.width + Self.margin * 2,
                               height: cardSize.height + Self.margin * 2)
        currentPanelSize = panelSize

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        // `.floating` (no `.screenSaver`): así el menú de Compartir del sistema
        // (nivel popUpMenu) aparece ENCIMA del panel y se puede tocar. Con
        // `.screenSaver` el panel tapaba el menú.
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        // Se puede arrastrar el panel desde cualquier parte del fondo y dejarlo
        // donde no moleste.
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        newPanel.hidesOnDeactivate = false

        currentText = text
        let view = MagicAnswerView(
            text: text,
            imageQuery: imageQuery,
            cardSize: cardSize,
            history: history,
            onSelectHistory: { [weak self] item in
                guard let self else { return }
                self.showInternal(text: item.text, imageQuery: item.imageQuery, near: self.lastAnchor)
            },
            onClearHistory: { [weak self] in self?.history.removeAll() },
            onShare: { [weak self] in self?.presentShare() },
            onClose: { [weak self] in
                Task { @MainActor in self?.hide() }
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        newPanel.contentView = hosting

        self.panel = newPanel
        self.hostingView = hosting
    }

    /// Abre el share sheet nativo de macOS (Mensajes, Mail, AirDrop, WhatsApp
    /// si está instalado, etc.) anclado al panel.
    private func presentShare() {
        guard let hostingView else { return }
        let picker = NSSharingServicePicker(items: [currentText])
        // Anclar cerca del botón Compartir (arriba-derecha de la card) y
        // desplegar hacia arriba para que no quede tapado por el panel.
        let bounds = hostingView.bounds
        let rect = NSRect(x: bounds.maxX - 60, y: bounds.maxY - 36, width: 1, height: 1)
        picker.show(relativeTo: rect, of: hostingView, preferredEdge: .maxY)
    }

    /// Ubica el panel al lado del cursor, clampeado dentro de la pantalla.
    private func positionPanel(near anchor: NSPoint) {
        guard let panel else { return }
        let size = currentPanelSize
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Por defecto: abajo-derecha del cursor.
        var x = anchor.x + 18
        var y = anchor.y - size.height - 18

        // Clamp horizontal.
        if x + size.width > visible.maxX { x = anchor.x - size.width - 18 }
        if x < visible.minX { x = visible.minX + 8 }
        // Clamp vertical.
        if y < visible.minY { y = anchor.y + 18 }
        if y + size.height > visible.maxY { y = visible.maxY - size.height - 8 }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return } // Esc
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}

// ── La tarjeta de respuesta ─────────────────────────────────────────────

private struct MagicAnswerView: View {
    let text: String
    var imageQuery: String? = nil
    var cardSize: NSSize = NSSize(width: 360, height: 300)
    var history: [MagicAnswerPanel.HistoryItem] = []
    var onSelectHistory: (MagicAnswerPanel.HistoryItem) -> Void = { _ in }
    var onClearHistory: () -> Void = {}
    let onShare: () -> Void
    let onClose: () -> Void

    /// Heurística: ¿la respuesta parece código? → fuente monoespaciada.
    private var looksLikeCode: Bool {
        guard text.contains("\n") else { return false }
        let markers = ["{", "}", ";", "()", "=>", "def ", "function", "import ",
                       "const ", "let ", "var ", "class ", "</", "/>", "#include", "println"]
        return markers.filter { text.contains($0) }.count >= 2
    }

    @State private var copied = false
    @State private var imageURL: URL? = nil
    @State private var searchingImage = false

    private let violet = Color(red: 0.55, green: 0.36, blue: 0.96)
    private let cyan = Color(red: 0.36, green: 0.80, blue: 0.95)

    var body: some View {
        // La card va dentro de un contenedor más grande (con margen
        // transparente) para que la SOMBRA tenga lugar y no se corte en un
        // borde cuadrado.
        card
            .frame(width: cardSize.width + 40, height: cardSize.height + 40)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: marca + acciones (chiquitas, arriba) + cerrar.
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [violet, cyan], startPoint: .leading, endPoint: .trailing)
                    )
                Text("Magic")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                historyMenu
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation { copied = true }
                }
                iconButton("square.and.arrow.up", help: "Compartir", action: onShare)
                iconButton("xmark", help: "Cerrar", action: onClose)
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 9)

            Divider().overlay(Color.white.opacity(0.08))

            // Cuerpo scrollable (imagen opcional arriba + texto).
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Texto primero, imagen después.
                    Text(text)
                        .font(looksLikeCode ? .system(size: 12, design: .monospaced)
                                            : .system(size: 13))
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if searchingImage {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.05))
                            .frame(height: 120)
                            .overlay(ProgressView().controlSize(.small))
                    } else if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                // scaledToFit: entra completa, sin recortarse.
                                image
                                    .resizable()
                                    .scaledToFit()
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
                }
                .padding(14)
            }
        }
        .task {
            guard let q = imageQuery else { return }
            searchingImage = true
            imageURL = await MagicImageSearch.thumbnailURL(for: q)
            searchingImage = false
        }
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2
                )
        )
        .shadow(color: violet.opacity(0.35), radius: 14)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }

    /// Menú de historial de respuestas (por si se cerró la ventana).
    private var historyMenu: some View {
        Menu {
            if history.isEmpty {
                Text("Sin historial")
            } else {
                ForEach(history) { item in
                    Button(item.preview) { onSelectHistory(item) }
                }
                Divider()
                Button("Limpiar historial", role: .destructive, action: onClearHistory)
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(.white.opacity(0.07))
                        .overlay(
                            Circle().strokeBorder(
                                LinearGradient(colors: [violet.opacity(0.7), cyan.opacity(0.7)],
                                               startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Historial")
    }

    /// Botón de solo-icono, chiquito, con el color de la marca.
    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(.white.opacity(0.07))
                        .overlay(
                            Circle().strokeBorder(
                                LinearGradient(colors: [violet.opacity(0.7), cyan.opacity(0.7)],
                                               startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                        )
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
