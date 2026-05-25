import SwiftUI

/// Vista de gestión de licencia de Nexo Whisper.
///
/// Dos modos según `licenseViewModel.licenseState`:
/// - `.free`  → CTA de compra + campo para ingresar license key existente.
/// - `.licensed` → estado actual de la activación + botón "Deactivate".
///
/// Importante: usa `LicenseViewModel.shared` (singleton) en vez de instanciar
/// uno nuevo, para que cualquier cambio de estado se propague también a
/// `FeatureGate` y a otras vistas que dependen del status de licencia.
struct LicenseManagementView: View {
    @ObservedObject private var licenseViewModel = LicenseViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPricingSheet = false
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection

                VStack(spacing: 32) {
                    if licenseViewModel.licenseState == .licensed {
                        activatedContent
                    } else {
                        purchaseContent
                    }
                }
                .padding(32)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showPricingSheet) {
            ProPricingSheet(isPresented: $showPricingSheet)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 24) {
            AppIconView()

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(licenseViewModel.licenseState == .licensed ? "License Active" : "Nexo Whisper License")
                            .font(.system(size: 32, weight: .bold))

                        Text("v\(appVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }
                }

                Text(licenseViewModel.licenseState == .licensed
                     ? "Thank you for supporting Nexo Whisper"
                     : "Transcribe what you say to text instantly with AI")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if licenseViewModel.licenseState == .licensed {
                    HStack(spacing: 40) {
                        Button {
                            if let url = URL(string: "\(NexoURLs.landing)/releases") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            featureItem(icon: "list.bullet.clipboard.fill", title: "Changelog", color: .blue)
                        }
                        .buttonStyle(.plain)

                        Button {
                            EmailSupport.openSupportEmail()
                        } label: {
                            featureItem(icon: "envelope.fill", title: "Email Support", color: .orange)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let url = URL(string: NexoURLs.docsHome) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            featureItem(icon: "book.fill", title: "Docs", color: .indigo)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 60)
    }

    // MARK: - Free (purchase) state

    private var purchaseContent: some View {
        VStack(spacing: 40) {
            // Free tier explainer — qué tenés gratis vs qué desbloquea Pro
            freeTierCard

            // Purchase card
            VStack(spacing: 24) {
                HStack {
                    Image(systemName: "infinity.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                    Text("Buy Once, Own Forever")
                        .font(.headline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                Button(action: { showPricingSheet = true }) {
                    Text("Get Nexo Whisper Pro")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 40) {
                    featureItem(icon: "bubble.left.and.bubble.right.fill", title: "Priority Support", color: .purple)
                    featureItem(icon: "infinity.circle.fill", title: "Lifetime Access", color: .blue)
                    featureItem(icon: "arrow.up.circle.fill", title: "Free Updates", color: .green)
                    featureItem(icon: "macbook", title: "1 Mac por licencia", color: .orange)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)

            // License activation form
            VStack(spacing: 20) {
                Text("Already have a license?")
                    .font(.headline)

                HStack(spacing: 12) {
                    TextField("Enter your license key", text: $licenseViewModel.licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .textCase(.uppercase)

                    Button(action: {
                        Task { await licenseViewModel.validateLicense() }
                    }) {
                        if licenseViewModel.isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Activate")
                                .frame(width: 80)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseViewModel.isValidating)
                }

                if let message = licenseViewModel.validationMessage {
                    Text(message)
                        .foregroundColor(licenseViewModel.validationSuccess ? .green : .red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)

            // Customer portal (para gestionar activaciones en otros devices)
            VStack(spacing: 20) {
                Text("¿Necesitás otra Mac?")
                    .font(.headline)

                HStack(spacing: 12) {
                    Text("Cada licencia activa 1 Mac. Si querés otra, comprá otra licencia (USD 7.99). Desde el portal podés también desactivar este device, ver invoices o pedir reembolso.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { licenseViewModel.openCustomerPortal() }) {
                        Text("Customer Portal")
                            .frame(width: 160)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
        }
    }

    /// Card que explica el modelo freemium: qué tenés gratis sin pagar nada,
    /// qué desbloquea la versión Pro. Importante para reducir la fricción —
    /// el user free debe saber que la app le sirve aún sin comprar.
    private var freeTierCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
                Text("You're using Nexo Whisper Free")
                    .font(.headline)
            }

            Text("La versión gratuita incluye todo lo esencial para dictar texto en tu Mac sin pagar nada.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                freeFeatureRow(icon: "checkmark.circle.fill", text: "Transcripción local (Whisper + Parakeet), todos los modelos")
                freeFeatureRow(icon: "checkmark.circle.fill", text: "Mejora con IA via Ollama local (sin internet, sin API key)")
                freeFeatureRow(icon: "checkmark.circle.fill", text: "Diccionario + reemplazos de palabras")
                freeFeatureRow(icon: "checkmark.circle.fill", text: "Atajos globales personalizables")
            }

            Divider()

            Text("Pro desbloquea:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                proFeatureRow(text: "Mejora con IA usando tu API key (Anthropic, OpenAI, Gemini, Groq, Mistral)")
                proFeatureRow(text: "Transcripción cloud (Groq, Deepgram, ElevenLabs, AssemblyAI, Soniox, Speechmatics, Mistral)")
                proFeatureRow(text: "Modos por App (Power Mode) — auto-configurar por aplicación")
                proFeatureRow(text: "Transcribir Audio (archivos .mp3, .wav, .m4a)")
                proFeatureRow(text: "Mejora vía CLI local (Claude Code, Codex, Antigravity, Copilot)")
                proFeatureRow(text: "7 prompts predefinidos extras (Chat, Email, Rewrite, Formal, Coding, Summary, Fun)")
                proFeatureRow(text: "Prompts custom — crear tus propios prompts")
            }
        }
        .padding(32)
        .background(CardBackground(isSelected: false))
        .shadow(color: .black.opacity(0.05), radius: 10)
    }

    private func freeFeatureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.system(size: 14))
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private func proFeatureRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    // MARK: - Licensed state

    private var activatedContent: some View {
        VStack(spacing: 32) {
            // Status Card
            VStack(spacing: 24) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    Text("License Active")
                        .font(.headline)
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.green))
                        .foregroundStyle(.white)
                }

                Divider()

                if let email = licenseViewModel.customerEmail {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundStyle(.secondary)
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                if let limit = licenseViewModel.activationLimit, limit > 0 {
                    let usage = licenseViewModel.activationUsage ?? 0
                    Text("Devices: \(usage) of \(limit) used")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Esta licencia activa 1 Mac. Para otra Mac, comprá otra licencia.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)

            // Customer portal + Deactivate
            VStack(alignment: .leading, spacing: 16) {
                Text("License Management")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button(action: { licenseViewModel.openCustomerPortal() }) {
                        Label("Customer Portal", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: {
                        Task { await licenseViewModel.removeLicense() }
                    }) {
                        Label("Deactivate This Device", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }

                Text("Deactivate frees this device's slot so you can activate another Mac with the same license.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
        }
    }

    private func featureItem(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
