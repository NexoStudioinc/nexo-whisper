import SwiftUI

// MARK: - Nexo Design System
//
// Sistema de diseño central de Nexo Whisper, alineado a macOS 26 (Tahoe).
// Filosofía: NATIVO primero — apoyarse en los controles, colores semánticos y
// materiales del sistema (que ya traen el look macOS 26), con el acento de marca
// (violeta → cyan) usado con moderación en momentos clave (heros, acentos, Magic
// Aura). Esto reemplaza el styling ad-hoc disperso por la app y unifica spacing,
// radios, tipografía y cards bajo un mismo lenguaje.
//
// Uso típico de una pantalla:
//   ScrollView { VStack(spacing: NexoSpacing.lg) { ... } .nexoPage() }

// MARK: Spacing

/// Escala de espaciado (múltiplos de 4). Usar SIEMPRE estos valores en vez de
/// números mágicos, para que el ritmo vertical sea consistente en toda la app.
enum NexoSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Padding estándar del borde de una pantalla.
    static let page: CGFloat = 24
    /// Ancho máximo del contenido de una pantalla (legibilidad en ventanas anchas).
    static let contentMaxWidth: CGFloat = 760
}

// MARK: Radii

/// Radios de esquina. macOS 26 (Liquid Glass) es notablemente más redondeado.
enum NexoRadius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let large: CGFloat = 16
}

// MARK: Brand color

extension Color {
    /// Violeta de marca Nexo.
    static let nexoViolet = Color(red: 0.55, green: 0.36, blue: 0.96)
    /// Cyan de marca Nexo.
    static let nexoCyan = Color(red: 0.36, green: 0.80, blue: 0.95)
}

extension ShapeStyle where Self == LinearGradient {
    /// Degradé de marca violeta → cyan (acento Nexo). Usar con moderación:
    /// heros, íconos destacados, estados activos.
    static var nexoAccent: LinearGradient {
        LinearGradient(colors: [.nexoViolet, .nexoCyan],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Card

/// Tarjeta-contenedor nativa macOS 26. Fondo de material del sistema, borde
/// sutil adaptativo y esquinas redondeadas. Reemplaza el glassmorphism manual
/// y los `GroupBox`/`RoundedRectangle` ad-hoc por un contenedor consistente.
struct NexoCard<Content: View>: View {
    var padding: CGFloat = NexoSpacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: NexoRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NexoRadius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
    }
}

/// Encabezado de sección consistente: SF Symbol opcional + título + subtítulo
/// opcional + contenido trailing opcional (botón, toggle).
struct NexoSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: NexoSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: NexoSpacing.sm)
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, systemImage != nil ? 26 : 0)
            }
        }
    }
}

extension NexoSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String? = nil, subtitle: LocalizedStringKey? = nil) {
        self.init(title: title, systemImage: systemImage, subtitle: subtitle) { EmptyView() }
    }
}

/// Hero de pantalla: ícono con acento de marca + título + descripción + badge
/// opcional (ej. "PREVIEW"). Unifica los distintos heros ad-hoc de la app.
struct NexoHero: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let systemImage: String
    var badge: LocalizedStringKey? = nil

    var body: some View {
        HStack(spacing: NexoSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.nexoAccent)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: NexoSpacing.sm) {
                    Text(title).font(.title2.bold())
                    if let badge { NexoBadge(badge) }
                }
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Badge chico (ej. "PREVIEW", "PRO") con el acento de marca.
struct NexoBadge: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.nexoViolet.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.nexoViolet)
    }
}

// MARK: - Button styles

/// Botón primario de marca (acento violeta→cyan). Para la acción principal.
struct NexoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, NexoSpacing.lg)
            .padding(.vertical, NexoSpacing.sm)
            .background(.nexoAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

/// Botón secundario sutil (material del sistema). Para acciones secundarias.
struct NexoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, NexoSpacing.lg)
            .padding(.vertical, NexoSpacing.sm)
            .background(.quaternary, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == NexoPrimaryButtonStyle {
    static var nexoPrimary: NexoPrimaryButtonStyle { .init() }
}
extension ButtonStyle where Self == NexoSecondaryButtonStyle {
    static var nexoSecondary: NexoSecondaryButtonStyle { .init() }
}

// MARK: - Page scaffold

extension View {
    /// Padding y ancho máximo estándar de una pantalla, alineado a la izquierda.
    /// Aplicar al VStack raíz del contenido de cada pantalla del detail.
    func nexoPage(maxWidth: CGFloat = NexoSpacing.contentMaxWidth) -> some View {
        self
            .padding(NexoSpacing.page)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
