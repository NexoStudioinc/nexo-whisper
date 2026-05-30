import SwiftUI
import WebKit

/// Paso del onboarding que presenta "Conocé Magic": un recorrido visual de las
/// funciones, renderizado con HTML/CSS animado dentro de un WebView (mismo
/// estilo que se reutiliza en la landing). Cuando el usuario termina o saltea,
/// el HTML avisa por el bridge `magic` y llamamos `onDone`.
struct OnboardingMagicView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.043, blue: 0.067).ignoresSafeArea()
            MagicWebView(onDone: onDone)
                .ignoresSafeArea()
        }
    }
}

private struct MagicWebView: NSViewRepresentable {
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "magic")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // fondo transparente
        webView.navigationDelegate = context.coordinator

        // Elegimos el HTML según el idioma de la app: inglés (base) o español.
        let isEnglish = LocalizationManager.shared.currentLanguage == .english
        let resource = isEnglish ? "OnboardingMagic-en" : "OnboardingMagic"
        if let url = Bundle.main.url(forResource: resource, withExtension: "html")
            ?? Bundle.main.url(forResource: "OnboardingMagic", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Fallback: si el recurso no está en el bundle, no bloqueamos el
            // onboarding — mostramos un mensaje mínimo con un botón de continuar.
            webView.loadHTMLString(Coordinator.fallbackHTML(english: isEnglish), baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "magic" {
                DispatchQueue.main.async { self.onDone() }
            }
        }

        static func fallbackHTML(english: Bool) -> String {
            let heading = english ? "Meet" : "Conocé"
            let subtitle = english
                ? "Select something, shake the mouse and talk to the AI — and it acts on it."
                : "Seleccioná algo, sacudí el mouse y hablale a la IA — y actúa sobre eso."
            let button = english ? "Get started" : "Empezar"
            return """
            <html><body style="margin:0;background:#0b0b11;color:#e9e9f1;font-family:-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;flex-direction:column;gap:18px">
            <h1 style="font-size:30px">\(heading) <span style="color:#8c5cf5">Magic</span></h1>
            <p style="opacity:.6;max-width:380px;text-align:center">\(subtitle)</p>
            <button onclick="window.webkit.messageHandlers.magic.postMessage('done')" style="font-size:15px;color:#fff;border:none;border-radius:999px;padding:12px 28px;background:linear-gradient(90deg,#8c5cf5,#5ccbf2);cursor:pointer">\(button)</button>
            </body></html>
            """
        }
    }
}
