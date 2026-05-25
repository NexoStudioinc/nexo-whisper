import SwiftUI
import AppKit

/// Sección "Licencia" dentro de Configuración.
///
/// Muestra estado actual (Free vs Pro) + acciones contextuales:
/// - Free → CTA "Get Pro" + campo para activar licencia existente
///   (sin abandonar Settings) + link a Customer Portal.
/// - Pro  → estado de activación, devices usados, opción de deactivar este
///   device + links a Changelog/Docs/Support.
///
/// Reemplaza la antigua pantalla dedicada de License Management — ahora todo
/// vive acá. Usa `LicenseViewModel.shared` para mantener consistencia con
/// el resto de la app (FeatureGate, ContentView, etc.).
struct LicenseSettingsSection: View {
    @ObservedObject private var licenseViewModel = LicenseViewModel.shared
    @State private var showPricingSheet = false
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if licenseViewModel.licenseState == .licensed {
                licensedHeader
                Divider()
                licensedActions
            } else {
                freeHeader
                Divider()
                activationForm
                Divider()
                freeActions
            }

            // Debug section: solo visible en builds LOCAL_BUILD (make local).
            // En builds Release/Distribución `isDebugBuild` retorna false y
            // todo el bloque se omite. Útil para QA del freemium sin recompilar.
            if licenseViewModel.isDebugBuild {
                Divider()
                debugSection
            }
        }
        .sheet(isPresented: $showPricingSheet) {
            ProPricingSheet(isPresented: $showPricingSheet)
        }
    }

    /// Sección de debug para developers — solo aparece en builds LOCAL_BUILD.
    /// Permite alternar entre estado `.free` y `.licensed` para validar el
    /// gating de features Pro sin necesidad de hacer dos builds separados.
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.circle.fill")
                    .foregroundStyle(.orange)
                Text("Debug · QA Mode")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                Spacer()
                Text("LOCAL_BUILD")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }

            Text("Build local — alterná entre Free y Licensed para validar el gating sin recompilar.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { licenseViewModel.debugForceFreeState },
                set: { _ in licenseViewModel.toggleDebugForceFreeState() }
            )) {
                Text("Forzar estado Free (override LOCAL_BUILD)")
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Licensed

    private var licensedHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("License Active")
                        .font(.headline)
                    ProBadge()
                }
                if let email = licenseViewModel.customerEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Thank you for supporting Nexo Whisper")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let limit = licenseViewModel.activationLimit,
                   let usage = licenseViewModel.activationUsage,
                   limit > 0 {
                    Text("Devices: \(usage) of \(limit) used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("v\(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var licensedActions: some View {
        HStack(spacing: 12) {
            Button {
                if let url = URL(string: "\(NexoURLs.landing)/releases") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Changelog", systemImage: "list.bullet.clipboard.fill")
            }

            Button {
                EmailSupport.openSupportEmail()
            } label: {
                Label("Support", systemImage: "envelope.fill")
            }

            Button {
                if let url = URL(string: NexoURLs.docsHome) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Docs", systemImage: "book.fill")
            }

            Button {
                licenseViewModel.openCustomerPortal()
            } label: {
                Label("Portal", systemImage: "person.crop.circle")
            }

            Spacer()

            Button(role: .destructive) {
                Task { await licenseViewModel.removeLicense() }
            } label: {
                Label("Deactivate", systemImage: "xmark.circle")
            }
        }
        .controlSize(.regular)
    }

    // MARK: - Free

    private var freeHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free Plan")
                    .font(.headline)
                Text("Transcripción local + Ollama local + System Default prompt")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                showPricingSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("Get Pro")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private var activationForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already have a license key?")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("Enter your license key", text: $licenseViewModel.licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button {
                    Task { await licenseViewModel.validateLicense() }
                } label: {
                    if licenseViewModel.isValidating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseViewModel.isValidating)
            }
            if let msg = licenseViewModel.validationMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(licenseViewModel.validationSuccess ? .green : .red)
            }
        }
    }

    private var freeActions: some View {
        HStack(spacing: 12) {
            Button {
                if let url = URL(string: NexoURLs.docsHome) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Docs", systemImage: "book.fill")
            }

            Button {
                EmailSupport.openSupportEmail()
            } label: {
                Label("Support", systemImage: "envelope.fill")
            }

            Spacer()

            Text("v\(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .controlSize(.regular)
    }
}
