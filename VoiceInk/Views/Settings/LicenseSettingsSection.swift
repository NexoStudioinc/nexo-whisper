import SwiftUI
import AppKit

/// Sección "Licencia" dentro de Configuración. Reemplaza la antigua pantalla
/// dedicada de License Management ahora que la app viene activada por defecto
/// para los compradores. Muestra estado, versión y acciones de soporte/docs.
struct LicenseSettingsSection: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("License Active")
                        .font(.headline)
                    Text("Thank you for supporting Nexo Whisper")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("v\(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            Divider()

            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "https://nexostudio.xyz/nexo-whisper/releases") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Changelog", systemImage: "list.bullet.clipboard.fill")
                }

                Button {
                    EmailSupport.openSupportEmail()
                } label: {
                    Label("Email Support", systemImage: "envelope.fill")
                }

                Button {
                    if let url = URL(string: "https://nexostudio.xyz/nexo-whisper/docs") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Docs", systemImage: "book.fill")
                }

                Spacer()
            }
            .controlSize(.regular)
        }
    }
}
