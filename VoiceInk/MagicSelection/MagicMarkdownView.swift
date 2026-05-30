import SwiftUI
import AppKit

/// Render de Markdown liviano para el panel de respuesta, estilo chat de LLM:
/// - Texto normal con formato inline (negrita, itálica, código inline, links).
/// - Bloques de código cercados (```), en un recuadro oscuro con fuente
///   monoespaciada, etiqueta de lenguaje y botón de copiar.
///
/// Tolerante a streaming: si un bloque ``` quedó abierto (todavía llegando
/// tokens), se renderiza igual como código hasta el final.
struct MagicMarkdownView: View {
    let text: String

    private let violet = Color(red: 0.55, green: 0.36, blue: 0.96)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MarkdownSegment.parse(text).enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let t):
                    inlineText(t)
                case .code(let code, let lang):
                    CodeBlock(code: code, language: lang)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Text(Self.attributed(raw))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Markdown inline preservando los saltos de línea del texto.
    private static func attributed(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }
}

// ── Bloque de código ─────────────────────────────────────────────────────

private struct CodeBlock: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation { copied = true }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// ── Parser de segmentos ───────────────────────────────────────────────────

enum MarkdownSegment {
    case text(String)
    case code(String, String?)

    /// Separa el texto en segmentos de texto y bloques de código cercados (```).
    static func parse(_ input: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        let lines = input.components(separatedBy: "\n")
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var inCode = false
        var codeLang: String? = nil

        func flushText() {
            if !textBuffer.isEmpty {
                let joined = textBuffer.joined(separator: "\n")
                if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(joined))
                }
                textBuffer.removeAll()
            }
        }
        func flushCode() {
            segments.append(.code(codeBuffer.joined(separator: "\n"), codeLang))
            codeBuffer.removeAll()
            codeLang = nil
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushText()
                    inCode = true
                    let fence = line.trimmingCharacters(in: .whitespaces)
                    let lang = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                }
            } else if inCode {
                codeBuffer.append(line)
            } else {
                textBuffer.append(line)
            }
        }
        // Cierre tolerante (streaming: bloque aún abierto).
        if inCode { flushCode() } else { flushText() }
        return segments
    }
}
