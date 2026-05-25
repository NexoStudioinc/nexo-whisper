import Foundation

/// URLs centralizadas de Nexo Whisper.
///
/// Razón de existir: cuando los paths finales del sitio se definan, cambia
/// solo este archivo y todas las URLs in-app quedan consistentes.
///
/// Estructura del dominio:
/// - `nexowhisper.com` → landing principal (en otro repo, todavía no
///   construido; el prompt para el agente está en
///   `~/.claude/projects/.../memory/landing_prompt_v2.md`).
/// - `docs.nexowhisper.com` → subdomain para documentación pública.
/// - Resto de subpaths bajo `nexowhisper.com/<TBD>` — sin decidir aún;
///   marcados con `// TODO(maxi)` para revisar antes del release.
enum NexoURLs {
    // MARK: - Bases

    static let landing      = "https://nexowhisper.com"
    static let docs         = "https://docs.nexowhisper.com"
    static let store        = "https://store.nexowhisper.com"
    static let supportEmail = "soporte@nexostudio.xyz"

    // MARK: - Producto / venta (Lemon Squeezy)

    /// Checkout del producto Nexo Whisper Pro en Lemon Squeezy.
    /// Product ID: 1087875 · Variant UUID: 3afa04ca-c09a-4032-a56e-868bf373b972
    /// Store custom domain: store.nexowhisper.com
    static let buy            = "\(store)/checkout/buy/3afa04ca-c09a-4032-a56e-868bf373b972"

    /// Customer portal de LS para gestionar activaciones, descargar invoices,
    /// pedir reembolsos y deactivar devices. Con custom domain → `/billing`.
    static let customerPortal = "\(store)/billing"

    /// Programa de afiliados (Lemon Squeezy lo provee por producto).
    /// TODO(maxi): apuntar a la URL real de LS afiliados cuando esté creada.
    static let affiliates     = "\(landing)/afiliados"

    // MARK: - Documentación (subdomain docs.nexowhisper.com)

    static let docsHome              = docs
    static let docsInstallation      = "\(docs)/instalacion"
    static let docsShortcuts         = "\(docs)/atajos"
    static let docsEnhancement       = "\(docs)/mejora-ia"
    static let docsAppProfiles       = "\(docs)/modos-por-app"
    static let docsRecommendedModels = "\(docs)/modelos-recomendados"
    static let docsContext           = "\(docs)/contexto"
    static let docsTroubleshooting   = "\(docs)/troubleshooting"
    static let docsEnhancementShortcuts = "\(docs)/atajos-mejora"

    // MARK: - Internal endpoints (announcements)

    /// JSON de anuncios in-app. El servicio está actualmente desactivado
    /// (solo `.stop()` en VoiceInk.swift); cuando se reactive hay que
    /// hostearlo en este endpoint.
    /// TODO(maxi): publicar el JSON.
    static let announcements = "\(landing)/announcements.json"
}
