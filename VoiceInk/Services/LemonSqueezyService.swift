import Foundation
import os

/// Errores comunes de cualquier servicio de licencias (vivía en `PolarService.swift`
/// que ya borramos; reubicado acá porque LemonSqueezyService es el único caller
/// ahora). Si en el futuro hay otro provider de licencias, este enum se queda acá
/// y se reusa — es vocabulario genérico, no específico de LS.
enum LicenseError: Error {
    /// 404 — la key no existe en este store (o nunca existió).
    case keyNotFound
    /// Excedió el límite de activations del producto (típicamente 3 Macs).
    case activationLimitReached
    /// HTTP no esperado (5xx, 401, etc).
    case serverError(Int)
}

/// Cliente para la API pública de Lemon Squeezy License Keys.
///
/// Reemplaza a `PolarService` (Nexo Whisper migró de Polar.sh a Lemon Squeezy).
///
/// La API de license keys de LS es pública: no requiere autenticación con
/// API key del seller. Se invoca directo desde el cliente con el license
/// key del usuario y un instance ID device-scoped.
///
/// Endpoints usados:
/// - POST /v1/licenses/activate    → primera activación en este device
/// - POST /v1/licenses/validate    → re-validación periódica del cache
/// - POST /v1/licenses/deactivate  → liberar slot (al desactivar desde la app)
///
/// Docs oficiales: https://docs.lemonsqueezy.com/api/license-api
final class LemonSqueezyService {
    private let baseURL = "https://api.lemonsqueezy.com/v1/licenses"
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LemonSqueezyService")

    // MARK: - Request helpers

    private func makeRequest(path: String, formBody: [String: String]) -> URLRequest {
        let url = URL(string: "\(baseURL)/\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // x-www-form-urlencoded body con URL-encoding manual.
        let encoded = formBody
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        request.httpBody = encoded.data(using: .utf8)

        return request
    }

    /// Wrapper para todas las llamadas: decodifica el JSON o lanza el error apropiado.
    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.serverError(0)
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? "(no body)"
            logger.error("🔑 LS request failed [HTTP \(httpResponse.statusCode)]: \(raw, privacy: .public)")

            // LS devuelve 404 cuando la key no existe, 400 con `error`
            // cuando la key está revocada/expirada/sin slots.
            switch httpResponse.statusCode {
            case 404:
                throw LicenseError.keyNotFound
            case 400:
                // Body típico: {"activated": false, "error": "..."}
                if let parsed = try? JSONDecoder().decode(LSErrorBody.self, from: data) {
                    let lower = parsed.error.lowercased()
                    if lower.contains("activation_limit") || lower.contains("limit") {
                        throw LicenseError.activationLimitReached
                    }
                }
                throw LicenseError.serverError(400)
            default:
                throw LicenseError.serverError(httpResponse.statusCode)
            }
        }

        return data
    }

    // MARK: - License operations

    /// Activa el license key en este device. Devuelve el `instance_id` que
    /// hay que persistir para futuras re-validaciones y deactivations.
    ///
    /// `instanceName` se muestra en el dashboard del customer (típicamente
    /// el hostname del Mac) para que pueda identificar qué activación borrar
    /// desde el portal si excede el límite.
    func activate(licenseKey: String, instanceName: String) async throws -> ActivateResponse {
        let request = makeRequest(path: "activate", formBody: [
            "license_key": licenseKey,
            "instance_name": instanceName
        ])

        let data = try await execute(request)
        let response = try JSONDecoder().decode(ActivateResponse.self, from: data)

        guard response.activated else {
            logger.error("🔑 LS activate returned activated=false: \(response.error ?? "no error msg", privacy: .public)")
            throw LicenseError.serverError(400)
        }

        logger.notice("🔑 LS license activated. instance_id=\(response.instance?.id ?? "?", privacy: .public)")
        return response
    }

    /// Re-valida una licencia ya activada. Llamar periódicamente (TTL del
    /// cache) para detectar reembolsos, desactivaciones remotas, etc.
    ///
    /// Si `valid == false`, el LicenseViewModel debería degradar a `.free`.
    func validate(licenseKey: String, instanceId: String) async throws -> ValidateResponse {
        let request = makeRequest(path: "validate", formBody: [
            "license_key": licenseKey,
            "instance_id": instanceId
        ])

        let data = try await execute(request)
        let response = try JSONDecoder().decode(ValidateResponse.self, from: data)
        return response
    }

    /// Libera el slot de activación de este device (el user puede usarlo
    /// en otra Mac). No falla si el instance ya no existe en LS — eso
    /// significa que alguien ya lo borró desde el portal.
    func deactivate(licenseKey: String, instanceId: String) async throws {
        let request = makeRequest(path: "deactivate", formBody: [
            "license_key": licenseKey,
            "instance_id": instanceId
        ])

        // Aceptamos 200 (success) o 404 (instance ya no existe → idempotente).
        do {
            _ = try await execute(request)
            logger.notice("🔑 LS license deactivated successfully")
        } catch LicenseError.keyNotFound {
            logger.notice("🔑 LS deactivate: instance was already gone, treating as success")
        }
    }
}

// MARK: - Response models

extension LemonSqueezyService {
    /// Forma del JSON de error genérico de LS para license endpoints.
    struct LSErrorBody: Codable {
        let activated: Bool?
        let error: String
    }

    /// Respuesta de POST /v1/licenses/activate.
    ///
    /// Estructura real de LS (campos opcionales para ser robustos a cambios futuros):
    /// ```json
    /// {
    ///   "activated": true,
    ///   "error": null,
    ///   "license_key": { "id": 1, "status": "active", "key": "...", "activation_limit": 3, "activation_usage": 1, ... },
    ///   "instance": { "id": "uuid", "name": "mac-hostname", "created_at": "..." },
    ///   "meta": { ... }
    /// }
    /// ```
    struct ActivateResponse: Codable {
        let activated: Bool
        let error: String?
        let licenseKey: LicenseKeyInfo?
        let instance: InstanceInfo?

        enum CodingKeys: String, CodingKey {
            case activated, error, instance
            case licenseKey = "license_key"
        }
    }

    /// Respuesta de POST /v1/licenses/validate.
    struct ValidateResponse: Codable {
        let valid: Bool
        let error: String?
        let licenseKey: LicenseKeyInfo?
        let instance: InstanceInfo?
        let meta: Meta?

        enum CodingKeys: String, CodingKey {
            case valid, error, instance, meta
            case licenseKey = "license_key"
        }

        struct Meta: Codable {
            let productName: String?
            let variantName: String?
            let customerEmail: String?

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case variantName = "variant_name"
                case customerEmail = "customer_email"
            }
        }
    }

    struct LicenseKeyInfo: Codable {
        let id: Int?
        let status: String
        let key: String?
        let activationLimit: Int?
        let activationUsage: Int?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case id, status, key
            case activationLimit = "activation_limit"
            case activationUsage = "activation_usage"
            case expiresAt = "expires_at"
        }
    }

    struct InstanceInfo: Codable {
        let id: String
        let name: String?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case createdAt = "created_at"
        }
    }
}
