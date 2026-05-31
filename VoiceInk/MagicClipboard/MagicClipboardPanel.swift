import AppKit
import SwiftUI

/// NSPanel que puede tomar foco (para el buscador). Esc lo cierra.
final class MagicClipboardKeyPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Panel flotante tipo Spotlight para el historial de portapapeles.
@MainActor
final class MagicClipboardPanel {
    private var panel: MagicClipboardKeyPanel?
    private let size = NSSize(width: 540, height: 440)

    var isVisible: Bool { panel != nil }

    func present(service: MagicClipboardService) {
        buildPanel(service: service)
        positionPanel()
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func buildPanel(service: MagicClipboardService) {
        panel?.orderOut(nil)
        let newPanel = MagicClipboardKeyPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.standardWindowButton(.closeButton)?.isHidden = true
        newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newPanel.standardWindowButton(.zoomButton)?.isHidden = true
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        newPanel.onCancel = { [weak self] in self?.hide() }

        let view = ClipboardPaletteView(service: service, onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        newPanel.contentView = hosting
        self.panel = newPanel
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Spotlight-style: centrado horizontal, en el tercio superior.
        let x = screen.midX - size.width / 2
        let y = screen.maxY - size.height - screen.height * 0.16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// ── La vista del panel ─────────────────────────────────────────────────

private enum PaletteTab: String, CaseIterable {
    case clipboard = "Clipboard"
    case emoji = "Emoji"
}

private struct ClipboardPaletteView: View {
    @ObservedObject var service: MagicClipboardService
    let onClose: () -> Void

    @State private var query = ""
    @State private var tab: PaletteTab = .clipboard
    @FocusState private var searchFocused: Bool

    private let violet = Color.nexoViolet
    private let cyan = Color.nexoCyan

    private var filteredItems: [ClipboardItem] {
        guard !query.isEmpty else { return service.history }
        return service.history.filter {
            ($0.text ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if tab == .clipboard {
                clipboardList
            } else {
                emojiGrid
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.98))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .padding(8)
        .onAppear { searchFocused = true }
    }

    // ── Header: buscador + pestañas ─────────────────────────────────────
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: tab == .emoji ? "face.smiling" : "doc.on.clipboard")
                .foregroundStyle(.nexoAccent)
            TextField(tab == .emoji ? "Search emoji…" : "Search what you copied…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.95))
                .focused($searchFocused)
                .onSubmit {
                    if tab == .clipboard, let first = filteredItems.first { service.paste(first) }
                }
            Picker("", selection: $tab) {
                ForEach(PaletteTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // ── Lista del portapapeles ──────────────────────────────────────────
    private var clipboardList: some View {
        Group {
            if service.history.isEmpty {
                emptyState("Nothing copied yet", "Copy something and it'll show up here.")
            } else if filteredItems.isEmpty {
                emptyState("No matches", "Try another search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems) { item in
                            Button { service.paste(item) } label: { row(item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func row(_ item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            if let icon = item.sourceIcon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "doc").frame(width: 22, height: 22).foregroundStyle(.secondary)
            }
            if case .image(let img) = item.kind {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(maxWidth: 64, maxHeight: 40, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(item.preview)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let app = item.sourceAppName {
                Text(app).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
    }

    // ── Grilla de emojis ────────────────────────────────────────────────
    private var emojiGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(Self.emojis.filter { query.isEmpty || $0.contains(query) }, id: \.self) { emoji in
                    Button { service.insertText(emoji) } label: {
                        Text(emoji).font(.system(size: 22))
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    private func emptyState(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // Set inicial de emojis (v1; ampliable / picker completo después).
    static let emojis: [String] = [
        "😀","😁","😂","🤣","😅","😊","😍","😘","😎","🤩","🥳","😏","😴","🤔","🙄","😮","😢","😭","😡","🤯",
        "👍","👎","👏","🙌","🙏","💪","🤝","👌","✌️","🤞","👀","🫶","❤️","🧡","💛","💚","💙","💜","🖤","🤍",
        "🔥","✨","🌟","⭐️","💯","✅","❌","⚠️","❓","❗️","💡","🎯","🚀","🎉","🎊","🏆","🥇","📌","📎","🔗",
        "💻","⌨️","🖱️","📱","🖥️","🗂️","📁","📄","📝","✏️","🔍","🔒","🔓","⚙️","🔔","📅","⏰","⌛️","💰","💳",
        "🍺","🍷","☕️","🍕","🍔","🌮","🍎","🥑","🐶","🐱","🦊","🦁","🐼","🌴","🌊","☀️","🌙","⚡️","❄️","🌈"
    ]
}
