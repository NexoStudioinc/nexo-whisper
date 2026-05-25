import SwiftUI
import SwiftData
import Charts

/// Vista raíz del Dashboard. Tras la migración freemium ya no muestra banner
/// de "días restantes de trial" (no hay trial). `MetricsContent` y
/// `DashboardPromotionsSection` siguen recibiendo `licenseState` para decidir
/// qué promos / CTAs mostrar (típicamente upgrade-to-Pro si `.free`).
struct MetricsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @ObservedObject private var licenseViewModel = LicenseViewModel.shared

    var body: some View {
        VStack {
            MetricsContent(
                modelContext: modelContext,
                licenseState: licenseViewModel.licenseState
            )
        }
        .background(Color(.controlBackgroundColor))
    }
}
