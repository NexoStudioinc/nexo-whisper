import SwiftUI
import AppKit

/// Sheet modal que muestra la comparativa Free vs Pro antes de abrir
/// el checkout de Lemon Squeezy.
///
/// Se invoca desde cualquier CTA "Get Pro" de la app: ProUpsellOverlay,
/// LicenseManagementView, LicenseSettingsSection. La razón de pasarlo
/// por este sheet (en vez de abrir el browser directo al checkout) es
/// reducir abandono — el user ve qué desbloquea exactamente, ve el precio,
/// y tiene oportunidad de activar una licencia existente sin volver atrás.
///
/// Estructura:
/// - Header: título + close button.
/// - Dos columnas: Free (sin acción) | Pro (acción primaria).
/// - Footer: "Already have a license?" con input + Activate.
///
/// Uso:
/// ```swift
/// @State private var showPricing = false
/// // ...
/// Button("Get Pro") { showPricing = true }
///   .sheet(isPresented: $showPricing) {
///       ProPricingSheet(isPresented: $showPricing)
///   }
/// ```
struct ProPricingSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var licenseViewModel = LicenseViewModel.shared
    @State private var showActivationForm = false

    /// Precio sugerido (placeholder; reemplazar por el real de LS).
    private let priceDisplay = "$7"
    private let priceCaption = "One-time payment · Lifetime updates"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 28) {
                    pricingColumns
                        .padding(.top, 24)

                    Divider()
                        .padding(.horizontal, 40)

                    if showActivationForm {
                        activationForm
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        alreadyHaveLicenseLink
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 720, height: 640)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Unlock Nexo Whisper Pro")
                        .font(.system(size: 20, weight: .bold))
                }
                Text("Tu compra única desbloquea todas las features Pro para siempre.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Pricing columns

    private var pricingColumns: some View {
        HStack(alignment: .top, spacing: 20) {
            freeColumn
            proColumn
        }
    }

    private var freeColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Free")
                    .font(.system(size: 22, weight: .bold))
                Text("Lo esencial, sin pagar nada")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("$0")
                    .font(.system(size: 32, weight: .heavy))
                Text("Forever")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                featureRow(included: true, "Transcripción local (Whisper + Parakeet)")
                featureRow(included: true, "Mejora con IA usando tu API key (BYOK)")
                featureRow(included: true, "Diccionario + reemplazos de palabras")
                featureRow(included: true, "Atajos globales personalizables")
                featureRow(included: true, "Historial + exportar CSV")
                featureRow(included: true, "1 prompt predefinido (System Default)")
            }

            Spacer()

            // Indicador visual de estado actual
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Tu plan actual")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.08))
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var proColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Pro")
                        .font(.system(size: 22, weight: .bold))
                    ProBadge()
                }
                Text("Todo lo de Free + features avanzadas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(priceDisplay)
                        .font(.system(size: 32, weight: .heavy))
                    Text("USD")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(priceCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                featureRow(included: true, "Todo lo de Free, más:")
                    .fontWeight(.semibold)
                featureRow(included: true, "Transcripción cloud (Groq, Deepgram, ElevenLabs, AssemblyAI, Soniox, Speechmatics, Mistral)")
                featureRow(included: true, "Modos por App (Power Mode)")
                featureRow(included: true, "Transcribir archivos de audio y video")
                featureRow(included: true, "Mejora vía CLI local (Claude Code, Codex, Antigravity, Copilot)")
                featureRow(included: true, "7 prompts predefinidos extras (Chat, Email, Coding, Summary, etc.)")
                featureRow(included: true, "Prompts custom ilimitados")
                featureRow(included: true, "Hasta 3 Macs por licencia")
                featureRow(included: true, "Soporte prioritario y actualizaciones gratis")
            }

            Spacer()

            Button(action: handleBuyClick) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Buy Pro · \(priceDisplay)")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.08),
                            Color.blue.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: Color.blue.opacity(0.1), radius: 8, y: 2)
        )
    }

    private func featureRow(included: Bool, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: included ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(included ? .green : .secondary.opacity(0.5))
                .font(.system(size: 14))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(included ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Activation form

    private var alreadyHaveLicenseLink: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showActivationForm = true
            }
        } label: {
            Text("Already have a license? **Activate it here**")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var activationForm: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Activate your license")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showActivationForm = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("Enter your license key", text: $licenseViewModel.licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button {
                    Task {
                        await licenseViewModel.validateLicense()
                        if licenseViewModel.validationSuccess {
                            // Activación exitosa → cerrar el sheet
                            isPresented = false
                        }
                    }
                } label: {
                    if licenseViewModel.isValidating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Activate")
                            .frame(minWidth: 70)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseViewModel.isValidating)
            }

            if let msg = licenseViewModel.validationMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(licenseViewModel.validationSuccess ? .green : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Actions

    private func handleBuyClick() {
        licenseViewModel.openPurchaseLink()
        // No cerramos el sheet acá: dejamos al user con la opción de
        // volver y activar después de pagar. Cerrarlo automáticamente
        // sería confuso (parece que pasó algo cuando solo se abrió browser).
    }
}
