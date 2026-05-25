import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("showLiveTextPreview") private var showLiveTextPreview = false

    @State private var activePopover: ActivePopoverState = .none

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 34
    // Sin los selectors laterales, el pill puede achicarse para ajustarse
    // mejor al waveform + indicador. Antes era 184pt; ahora 140pt.
    private let compactWidth: CGFloat = 140
    private let expandedWidth: CGFloat = 280
    private let compactCornerRadius: CGFloat = 17
    private let expandedCornerRadius: CGFloat = 14

    // true when live transcript is streaming in during recording
    private var hasLiveTranscript: Bool {
        showLiveTextPreview
            && stateProvider.recordingState == .recording
            && !stateProvider.partialTranscript.isEmpty
    }

    // Pill simplificada: solo onda + indicador. Los selectors de prompt
    // de mejora y App Profile se sacaron del pill (ahora se manejan vía
    // hotkeys configurables + menubar). El widget queda minimalista para
    // no distraer durante la grabación.
    private var controlBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter
            )

            Spacer(minLength: 0)
        }
        .frame(height: controlBarHeight)
        .padding(.horizontal, 8)
    }

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if hasLiveTranscript {
                LiveTranscriptView(text: stateProvider.partialTranscript)
                Divider().background(Color.white.opacity(0.15))
            }
        }
    }

    var body: some View {
        if windowManager.isVisible {
            VStack(spacing: 0) {
                transcriptSection
                controlBar
            }
            .frame(width: hasLiveTranscript ? expandedWidth : compactWidth)
            // Negro casi sólido con un toque de transparencia. Antes era
            // glassmorphism (muy transparente), pero molestaba la legibilidad.
            // Mantiene look minimalista pero deja ver el fondo apenas.
            .background(Color.black.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: hasLiveTranscript ? expandedCornerRadius : compactCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
            .animation(.easeInOut(duration: 0.3), value: hasLiveTranscript)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
