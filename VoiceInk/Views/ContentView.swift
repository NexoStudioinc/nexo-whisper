import SwiftUI
import SwiftData
import OSLog

// ViewType enum with all cases
enum ViewType: String, CaseIterable, Identifiable {
    case metrics = "Dashboard"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case models = "AI Models"
    case enhancement = "Enhancement"
    case magicSelection = "Magic"
    case powerMode = "Power Mode"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case settings = "Settings"
    case license = "License"

    var id: String { rawValue }

    func displayName(language: String) -> String {
        AppText.t(rawValue, language: language)
    }

    var icon: String {
        switch self {
        case .metrics: return "gauge.medium"
        case .transcribeAudio: return "waveform.circle.fill"
        case .history: return "doc.text.fill"
        case .models: return "brain.head.profile"
        case .enhancement: return "wand.and.stars"
        case .magicSelection: return "cursorarrow.rays"
        case .powerMode: return "sparkles.square.fill.on.square"
        case .permissions: return "shield.fill"
        case .audioInput: return "mic.fill"
        case .dictionary: return "character.book.closed.fill"
        case .settings: return "gearshape.fill"
        case .license: return "checkmark.seal.fill"
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ContentView")
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var selectedView: ViewType? = .metrics
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    // Usa el singleton para que cualquier vista que escuche `LicenseViewModel.shared`
    // (o que pase por `FeatureGate`) vea el mismo estado consistente.
    @ObservedObject private var licenseViewModel = LicenseViewModel.shared

    private var visibleViewTypes: [ViewType] {
        ViewType.allCases.filter { viewType in
            if viewType == .powerMode {
                return powerModeUIFlag
            }
            // Licencia ya no es item del sidebar: se accede desde Configuración
            // como una sección al final. La app viene "activada" por defecto
            // tras la compra, así que no hace falta exponer un slot dedicado.
            if viewType == .license {
                return false
            }
            // Entrada de Audio y Permisos se acceden desde Configuración
            // (acordeón vertical estilo iOS). Las views completas siguen
            // disponibles vía .navigateToDestination para abrir desde botón.
            if viewType == .audioInput || viewType == .permissions {
                return false
            }
            return true
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                Section {
                    // App Header — el SidebarLogo ya trae el icono + texto
                    // "Nexo Whisper" embebidos como banner horizontal, con
                    // variantes light y dark del asset catalog.
                    //
                    // Indicador visible del plan actual (Free / PRO) debajo
                    // del logo. Si el user está en Pro, mostramos el ProBadge
                    // como confirmación visual ("estoy usando lo pago, no la
                    // free"). Si está en Free, mostramos un mini-CTA discreto
                    // que abre el sheet de pricing.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image("SidebarLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 170, maxHeight: 60)
                            Spacer(minLength: 0)
                        }
                        sidebarPlanIndicator
                    }
                    .padding(.vertical, 6)
                }

                ForEach(visibleViewTypes) { viewType in
                    Section {
                        NavigationLink(value: viewType) {
                            SidebarItemView(viewType: viewType)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Nexo Whisper")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            if let selectedView = selectedView {
                detailView(for: selectedView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedView.displayName(language: appLanguage))
            } else {
                Text(AppText.t("Select a view", language: appLanguage))
                    .foregroundColor(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 640)
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                switch destination {
                case "Settings":
                    selectedView = .settings
                case "AI Models":
                    selectedView = .models
                case "License":
                    selectedView = .license
                case "History":
                    selectedView = .history
                case "Permissions":
                    selectedView = .permissions
                case "Audio Input":
                    selectedView = .audioInput
                case "Enhancement":
                    selectedView = .enhancement
                case "Transcribe Audio":
                    selectedView = .transcribeAudio
                case "Power Mode":
                    selectedView = .powerMode
                default:
                    break
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch viewType {
        case .metrics:
            MetricsView()
        case .models:
            ModelManagementView()
        case .enhancement:
            EnhancementSettingsView()
        case .magicSelection:
            MagicSelectionView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            InlineHistoryView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView(whisperPrompt: whisperModelManager.whisperPrompt)
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView()
        case .license:
            LicenseManagementView()
        case .permissions:
            PermissionsView()
        }
    }

    /// Indicador visual del plan actual debajo del logo en el sidebar.
    /// - Pro → ProBadge prominente (confirma al user que está usando el
    ///   plan pago, especialmente útil en LOCAL_BUILD para no dudar).
    /// - Free → mini-CTA "Upgrade" discreto que navega a la pantalla
    ///   de Licencia donde se abre el ProPricingSheet.
    @ViewBuilder
    private var sidebarPlanIndicator: some View {
        if licenseViewModel.isPro {
            HStack(spacing: 6) {
                ProBadge()
                Text("Active")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        } else {
            Button {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "License"]
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("Free · Upgrade")
                        .font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SidebarItemView: View {
    let viewType: ViewType
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: viewType.icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, height: 24)

            Text(viewType.displayName(language: appLanguage))
                .font(.system(size: 14, weight: .medium))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }
}
