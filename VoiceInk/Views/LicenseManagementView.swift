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
            VStack(alignment: .leading, spacing: NexoSpacing.lg) {
                heroSection

                if licenseViewModel.licenseState == .licensed {
                    activatedContent
                } else {
                    purchaseContent
                }
            }
            .nexoPage()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showPricingSheet) {
            ProPricingSheet(isPresented: $showPricingSheet)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: NexoSpacing.lg) {
            AppIconView()

            VStack(spacing: NexoSpacing.md) {
                HStack(spacing: NexoSpacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.nexoAccent)

                    HStack(alignment: .lastTextBaseline, spacing: NexoSpacing.sm) {
                        Text(licenseViewModel.licenseState == .licensed ? "License Active" : "Nexo Whisper License")
                            .font(.system(size: 28, weight: .bold))

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
        .frame(maxWidth: .infinity)
        .padding(.vertical, NexoSpacing.xl)
    }

    // MARK: - Free (purchase) state

    private var purchaseContent: some View {
        VStack(alignment: .leading, spacing: NexoSpacing.lg) {
            // Free tier explainer — qué tenés gratis vs qué desbloquea Pro
            freeTierCard

            // Purchase card
            NexoCard {
                VStack(alignment: .leading, spacing: NexoSpacing.md) {
                    NexoSectionHeader("Upgrade to Pro", systemImage: "sparkles",
                                      subtitle: "Buy once, own forever. Unlock cloud transcription, your own AI keys and more.")
                    Divider()

                    Button(action: { showPricingSheet = true }) {
                        Text("Get Nexo Whisper Pro")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.nexoPrimary)

                    HStack(spacing: 40) {
                        featureItem(icon: "bubble.left.and.bubble.right.fill", title: "Priority Support", color: .purple)
                        featureItem(icon: "infinity.circle.fill", title: "Lifetime Access", color: .blue)
                        featureItem(icon: "arrow.up.circle.fill", title: "Free Updates", color: .green)
                        featureItem(icon: "macbook", title: "1 Mac per license", color: .orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, NexoSpacing.xs)
                }
            }

            // License activation form
            NexoCard {
                VStack(alignment: .leading, spacing: NexoSpacing.md) {
                    NexoSectionHeader("Already have a license?", systemImage: "key.fill",
                                      subtitle: "Enter your license key to activate this Mac.")
                    Divider()

                    HStack(spacing: NexoSpacing.md) {
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
                    }
                }
            }

            // Customer portal (para gestionar activaciones en otros devices)
            NexoCard {
                VStack(alignment: .leading, spacing: NexoSpacing.md) {
                    NexoSectionHeader("Need another Mac?", systemImage: "macbook.and.iphone",
                                      subtitle: "Each license activates 1 Mac.")
                    Divider()

                    HStack(spacing: NexoSpacing.md) {
                        Text("Each license activates 1 Mac. To use another Mac, buy a second license. From the portal you can also deactivate this device, view invoices or request a refund.")
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
            }
        }
    }

    /// Card que explica el modelo freemium: qué tenés gratis sin pagar nada,
    /// qué desbloquea la versión Pro. Importante para reducir la fricción —
    /// el user free debe saber que la app le sirve aún sin comprar.
    private var freeTierCard: some View {
        NexoCard {
            VStack(alignment: .leading, spacing: NexoSpacing.md) {
                NexoSectionHeader("You're using Nexo Whisper Free", systemImage: "gift.fill",
                                  subtitle: "The free version includes everything essential to dictate text on your Mac at no cost.")
                Divider()

                VStack(alignment: .leading, spacing: NexoSpacing.sm) {
                    freeFeatureRow(icon: "checkmark.circle.fill", text: "Local transcription (Whisper + Parakeet), all models")
                    freeFeatureRow(icon: "checkmark.circle.fill", text: "AI enhancement via local Ollama (no internet, no API key)")
                    freeFeatureRow(icon: "checkmark.circle.fill", text: "Dictionary + word replacements")
                    freeFeatureRow(icon: "checkmark.circle.fill", text: "Customizable global shortcuts")
                }

                Divider()

                Text("Pro unlocks:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: NexoSpacing.sm) {
                    proFeatureRow(text: "AI enhancement using your own API key (Anthropic, OpenAI, Gemini, Groq, Mistral)")
                    proFeatureRow(text: "Cloud transcription (Groq, Deepgram, ElevenLabs, AssemblyAI, Soniox, Speechmatics, Mistral)")
                    proFeatureRow(text: "Power Mode (per-app modes) — auto-configure by application")
                    proFeatureRow(text: "Audio transcription (.mp3, .wav, .m4a files)")
                    proFeatureRow(text: "Enhancement via local CLI (Claude Code, Codex, Antigravity, Copilot)")
                    proFeatureRow(text: "7 extra predefined prompts (Chat, Email, Rewrite, Formal, Coding, Summary, Fun)")
                    proFeatureRow(text: "Custom prompts — create your own prompts")
                }
            }
        }
    }

    private func freeFeatureRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.system(size: 14))
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private func proFeatureRow(text: LocalizedStringKey) -> some View {
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
        VStack(alignment: .leading, spacing: NexoSpacing.lg) {
            // Status Card
            NexoCard {
                VStack(alignment: .leading, spacing: NexoSpacing.md) {
                    NexoSectionHeader(title: "License Active", systemImage: "checkmark.circle.fill",
                                      subtitle: "Your Pro license is activated on this Mac.") {
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
                        Text("This license activates 1 Mac. To use another Mac, buy a second license.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // Customer portal + Deactivate
            NexoCard {
                VStack(alignment: .leading, spacing: NexoSpacing.md) {
                    NexoSectionHeader("License Management", systemImage: "gearshape.2",
                                      subtitle: "Manage your subscription or free up this device's slot.")
                    Divider()

                    HStack(spacing: NexoSpacing.md) {
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
            }
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
