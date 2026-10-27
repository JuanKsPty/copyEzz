import Foundation

/// Modelo de visión local vía Ollama.
public struct OllamaBackend: Backend {
    public var baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }

    public static func requestBody(png: Data, model: String, context: String? = nil) -> [String: Any] {
        var options: [String: Any] = ["temperature": 0]
        if let context, !context.isEmpty {
            options["num_ctx"] = contextLength(for: context)
        }
        return [
            "model": model,
            "stream": false,
            "keep_alive": "30m",  // mantiene el modelo en memoria: ~0.6 s en caliente vs ~6 s en frío
            "options": options,
            "messages": [
                ["role": "system", "content": Prompt.system(context: context)],
                ["role": "user", "content": Prompt.userText, "images": [png.base64EncodedString()]],
            ],
        ]
    }

    /// Ollama recorta en silencio lo que no cabe en su ventana por defecto (unos miles de tokens), y la
    /// captura sola ya ocupa ~2 mil: con contexto se agranda para que entren el material, la imagen y la
    /// respuesta. Cuenta ~3 bytes por token, de sobra para texto en español.
    static func contextLength(for context: String) -> Int {
        let tokens = context.utf8.count / 3 + 4096
        return max(8192, (tokens + 4095) / 4096 * 4096)
    }

    public static func parseResponse(data: Data, status: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            throw CopyEzzError("Ollama: \(json["error"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: status))")
        }
        guard let content = (json["message"] as? [String: Any])?["content"] as? String else {
            throw CopyEzzError("Ollama: respuesta inesperada")
        }
        return content
    }

    public func solve(png: Data, model: String, context: String?) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "api/chat"), timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try Self.requestBody(png: png, model: model, context: context).jsonData()
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CopyEzzError("Ollama no responde en :11434 (¿brew services start ollama?)")
        }
        return try Self.parseResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
