import SwiftUI

struct OnboardingTutorialView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var transcribedText: String = ""
    @State private var isTextFieldFocused: Bool = false
    @State private var showingShortcutHint: Bool = true
    @FocusState private var isFocused: Bool
    @State private var showMagic = false

    var body: some View {
        if showMagic {
            // Tras el tutorial de Whisper, presentamos "Conocé Magic" y al
            // terminar/saltear se completa el onboarding.
            OnboardingMagicView(onDone: { hasCompletedOnboarding = true })
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
        GeometryReader { geometry in
            ZStack {
                // Reusable background
                OnboardingBackgroundView()

                HStack(spacing: 0) {
                    // Left side - Tutorial instructions
                    // Layout compacto: padding 28, tipografías reducidas y
                    // spacing entre bloques recortado para que TODO el flujo
                    // (titulo + shortcut + 4 pasos + 2 botones) entre en una
                    // ventana de 900x640 sin que el boton quede cortado.
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Try It Out!")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Let's test your Nexo Whisper setup.")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .lineSpacing(2)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your Shortcut")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)

                            ShortcutPreviewView(shortcut: ShortcutStore.shortcut(for: .primaryRecording))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(1...4, id: \.self) { step in
                                instructionStep(number: step, text: getInstructionText(for: step))
                            }
                        }

                        Spacer(minLength: 0)

                        Button(action: {
                            withAnimation { showMagic = true }
                        }) {
                            Text("Next")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 180, height: 40)
                                .background(Color.accentColor)
                                .cornerRadius(20)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(28)
                    .frame(width: geometry.size.width * 0.5)
                    
                    // Right side - Interactive area
                    VStack {
                        // Magical text editor area
                        ZStack {
                            // Glowing background
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .overlay(
                                    // Subtle gradient overlay
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.05),
                                            Color.black.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.accentColor.opacity(0.1), radius: 15, x: 0, y: 0)
                            
                            // Text editor with custom styling
                            TextEditor(text: $transcribedText)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .focused($isFocused)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .foregroundColor(.white)
                                .padding(20)
                            
                            // Placeholder text with magical appearance
                            if transcribedText.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 36))
                                        .foregroundColor(.white.opacity(0.3))
                                    
                                    Text("Click here and start speaking...")
                                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .allowsHitTesting(false)
                            }
                            
                            // Subtle animated border
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(isFocused ? 0.4 : 0.1),
                                            Color.accentColor.opacity(isFocused ? 0.2 : 0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                                .animation(.easeInOut(duration: 0.3), value: isFocused)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(60)
                    .frame(width: geometry.size.width * 0.5)
                }
            }
        }
        .onAppear {
            animateIn()
            isFocused = true
        }
        }
    }

    private func getInstructionText(for step: Int) -> LocalizedStringKey {
        switch step {
        case 1: return "Click the text area on the right"
        case 2: return "Press your shortcut key"
        case 3: return "Speak something"
        case 4: return "Press your shortcut key again"
        default: return ""
        }
    }

    private func instructionStep(number: Int, text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(2)
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }
}
