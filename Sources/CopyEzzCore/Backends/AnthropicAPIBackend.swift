import Foundation

/// API de Anthropic por HTTP directo (no hay SDK oficial para Swift).
public struct AnthropicAPIBackend: Backend {
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public var apiKey: String?
    public var baseURL: URL

    public init(apiKey: String?, baseURL: URL = URL(string: "https://api.anthropic.com")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    /// Haiku 4.5 no acepta `effort` ni los fallbacks de servidor; el resto de modelos actuales sí.
    static func supportsEffortAndFallbacks(_ model: String) -> Bool {
        !model.contains("haiku")
    }

    public static func requestBody(png: Data, model: String, context: String? = nil) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system(context: context),
            "messages": [["role": "user", "content": MessageContent.imageAndText(png: png)]],
        ]
        if supportsEffortAndFallbacks(model) {
            body["output_config"] = ["effort": "low"]
            body["fallbacks"] = "default"
        }
        return body
    }

    /// Con contexto, el system prompt se marca para la caché: las capturas siguientes (dentro de 5 min)
    /// leen el material de la caché, más rápido y a ~10 % del costo, en vez de procesarlo de nuevo.
    static func system(context: String?) -> Any {
        guard let context, !context.isEmpty else { return Prompt.system }
        return [["type": "text", "text": Prompt.system(context: context), "cache_control": ["type": "ephemeral"]]]
    }

    public static func makeRequest(
        baseURL: URL, apiKey: String, png: Data, model: String, context: String? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "v1/messages"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if supportsEffortAndFallbacks(model) {
            request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try requestBody(png: png, model: model, context: context).jsonData()
        return request
    }

    /// Texto de la respuesta o un error con mensaje corto.
    public static func parseResponse(data: Data, status: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String
            switch status {
            case 401: throw CopyEzzError("API key inválida")
            case 404: throw CopyEzzError("modelo no disponible: \(message ?? "404")")
            case 429: throw CopyEzzError("rate limit de la API, reintenta")
            case 529: throw CopyEzzError("la API está saturada, reintenta")
            default: throw CopyEzzError("API \(status): \(message ?? HTTPURLResponse.localizedString(forStatusCode: status))")
            }
        }
        if json["stop_reason"] as? String == "refusal" {
            throw CopyEzzError("el modelo rechazó la solicitud")
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        return blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
    }

    public func solve(png: Data, model: String, context: String?) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw CopyEzzError("falta ANTHROPIC_API_KEY") }
        let request = try Self.makeRequest(baseURL: baseURL, apiKey: apiKey, png: png, model: model, context: context)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CopyEzzError("sin conexión con la API")
        }
        return try Self.parseResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
