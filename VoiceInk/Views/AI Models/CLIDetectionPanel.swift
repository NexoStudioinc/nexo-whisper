import SwiftUI

/// Detecta qué CLIs compatibles están instalados en el PATH del usuario y
/// permite seleccionar uno con un clic. Reemplaza el flujo manual donde el
/// usuario tenía que armar el comando a mano. La configuración avanzada
/// (campo de comando custom) sigue disponible debajo para power users.
struct CLIDetectionPanel: View {
    @ObservedObject var aiService: AIService
    @State private var availability: [LocalCLITemplate: Bool] = [:]
    @State private var isDetecting = true

    private let detectableClients: [LocalCLITemplate] = [.claude, .codex, .gemini, .copilot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars.inverse")
                    .foregroundStyle(.blue)
                Text("Auto-detected installed CLIs")
                    .font(.headline)
            }

            Text("We'll use your personal subscription of the CLI you choose. We don't charge for model usage.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isDetecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Detecting installed clients...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(detectableClients) { client in
                        cliRow(client)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
        .task {
            await detectAll()
        }
    }

    @ViewBuilder
    private func cliRow(_ client: LocalCLITemplate) -> some View {
        let isInstalled = availability[client] ?? false
        let isActive = aiService.localCLITemplateSelection == client

        HStack(spacing: 10) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isInstalled ? .green : .secondary)

            Text(client.displayName)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))

            Spacer()

            if isInstalled {
                if isActive {
                    Text("Active CLI")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                } else {
                    Button("Use this") {
                        aiService.loadLocalCLITemplate(client)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            } else if let installURL = client.installHelpURL {
                Button {
                    NSWorkspace.shared.open(installURL)
                } label: {
                    Text("How to install")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            } else {
                Text("Not installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    private func detectAll() async {
        var results: [LocalCLITemplate: Bool] = [:]
        for client in detectableClients {
            results[client] = await LocalCLIService.isBinaryAvailable(named: client.binaryName)
        }
        await MainActor.run {
            self.availability = results
            self.isDetecting = false
        }
    }
}
