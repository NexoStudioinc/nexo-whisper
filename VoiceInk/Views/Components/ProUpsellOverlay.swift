import SwiftUI
import AppKit

/// Overlay full-screen que reemplaza el contenido de una vista cuando el
/// user no tiene licencia Pro y la feature está gateada.
///
/// Uso típico:
/// ```swift
/// var body: some View {
///     if FeatureGate.isAvailable(.fileTranscription) {
///         realContent
///     } else {
///         ProUpsellOverlay(feature: .fileTranscription,
///                          icon: "waveform.badge.mic",
///                          title: "Transcribe Audio Files",
///                          description: "Procesá archivos .mp3, .wav, .m4a y video con Whisper local.")
///     }
/// }
/// ```
///
/// Razón de diseño: en vez de mostrar candados pequeños en cada control
/// (overlay parcial), bloqueamos la pantalla entera. Más claro para el user
/// free — entiende inmediatamente que la feature completa es Pro, y el CTA
/// "Get Pro" está visible sin scroll.
struct ProUpsellOverlay: View {
    let feature: FeatureGate.Feature
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    var bullets: [LocalizedStringKey] = []

    @ObservedObject private var licenseViewModel = LicenseViewModel.shared
    @State private var showPricingSheet = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Icon + Pro badge
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(20)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                    )

                ProBadge()
                    .offset(x: 8, y: -4)
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
                            Text(bullet)
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
                .frame(maxWidth: 460)
            }

            // CTAs — el botón principal abre el ProPricingSheet (comparativa
            // Free vs Pro + precio + activación). Reduce abandono vs abrir
            // browser directo al checkout. El sheet adentro tiene su propia
            // opción "Already have a license? Activate" plegable.
            Button(action: { showPricingSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Conseguí Nexo Whisper Pro")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: 280)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showPricingSheet) {
            ProPricingSheet(isPresented: $showPricingSheet)
        }
    }
}
