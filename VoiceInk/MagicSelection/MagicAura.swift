import SwiftUI
import AppKit

/// Color configurable del aura (el glow del cursor) de Magic Aura.
/// Si el usuario no eligió ninguno, se usa el degradé por defecto violeta→cyan.
enum MagicAura {
    private static let key = "magicSelection.auraColor"

    /// Colores por defecto (paleta Nexo).
    static let defaultPrimary = Color(red: 0.55, green: 0.36, blue: 0.96)   // violeta
    static let defaultSecondary = Color(red: 0.36, green: 0.80, blue: 0.95) // cyan

    /// Color elegido por el usuario (nil = usar el degradé por defecto).
    static var customColor: Color? {
        guard let hex = UserDefaults.standard.string(forKey: key), !hex.isEmpty else { return nil }
        return Color(magicHex: hex)
    }

    static func setColor(_ color: Color?) {
        if let color, let hex = color.magicHexString {
            UserDefaults.standard.set(hex, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Color principal del aura (núcleo).
    static var primary: Color { customColor ?? defaultPrimary }
    /// Color secundario (halo exterior). Con color custom, un tono del mismo.
    static var secondary: Color {
        if let c = customColor { return c.opacity(0.85) }
        return defaultSecondary
    }
}

extension Color {
    init?(magicHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xff) / 255,
            green: Double((v >> 8) & 0xff) / 255,
            blue: Double(v & 0xff) / 255
        )
    }

    var magicHexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
