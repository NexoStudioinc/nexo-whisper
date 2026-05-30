import SwiftUI

/// Sección de **Magic** en Ajustes generales. A partir del rediseño, acá queda
/// SOLO el toggle de activar/desactivar — toda la configuración (chips,
/// traducir, panel, sensibilidad) vive en la pantalla dedicada "Magic" del
/// sidebar, para no entorpecer los Ajustes y dejar que el feature crezca.
struct MagicSelectionSection: View {
    @AppStorage("magicSelection.enabled") private var enabled = false

    var body: some View {
        Section {
            Toggle("Activar Magic Aura (preview)", isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    Task { @MainActor in
                        MagicSelectionService.shared.isEnabled = newValue
                    }
                }

            HStack(spacing: 6) {
                Image(systemName: "sidebar.squares.left")
                    .foregroundStyle(.secondary)
                Text("Configurá los botones de acción, la traducción y el comportamiento del panel desde **Magic** en la barra lateral.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 6) {
                Label("Magic Aura", systemImage: "cursorarrow.rays")
                Text("PREVIEW")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.purple.opacity(0.2)))
                    .foregroundStyle(.purple)
            }
        }
    }
}
