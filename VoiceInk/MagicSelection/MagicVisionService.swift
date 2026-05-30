import AppKit
import Vision
import OSLog

/// Tier 3 (visión) — versión 1: cuando NO hay texto accesible por AX ni por el
/// portapapeles (terminales, imágenes, PDFs, Electron sin árbol), captura la
/// región alrededor del cursor y le pasa **OCR on-device (Vision framework)**
/// para extraer el texto. Gratis, local, privado. No necesita un VLM remoto.
///
/// (El reconocimiento de imágenes SIN texto —"qué es esta foto"— necesita un VLM
/// con entrada de imagen; queda para una fase posterior.)
enum MagicVisionService {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "MagicVisionService"
    )

    /// Extrae texto por OCR de una región alrededor de `point` (coords NSScreen).
    /// `box` es el lado de la región a capturar (ancho × alto*0.6). Área amplia
    /// para que lea suficiente contexto alrededor del cursor.
    static func textUnderCursor(at point: NSPoint, box: CGFloat = 900) async -> String? {
        guard let image = captureRegion(around: point, box: box) else {
            logger.info("Vision: no pude capturar la región bajo el cursor")
            return nil
        }
        return await recognizeText(in: image)
    }

    // MARK: - Captura

    private static func captureRegion(around point: NSPoint, box: CGFloat) -> CGImage? {
        // CGWindowListCreateImage usa coords con origen arriba-izquierda; el
        // `point` viene en NSScreen (abajo-izquierda) → flip de Y.
        guard let primary = NSScreen.screens.first else { return nil }
        let flippedY = primary.frame.height - point.y
        // Región más ancha que alta (el texto fluye horizontal).
        let w = box
        let h = box * 0.6
        let rect = CGRect(
            x: point.x - w / 2,
            y: flippedY - h / 2,
            width: w,
            height: h
        )
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
    }

    // MARK: - OCR (Vision)

    private static func recognizeText(in image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    logger.error("Vision OCR error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Idiomas comunes (es/en) para mejor precisión.
            request.recognitionLanguages = ["es-ES", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    logger.error("Vision handler.perform falló: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
