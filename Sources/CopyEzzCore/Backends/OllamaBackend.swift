import Foundation

/// Modelo de visión local vía Ollama.
public struct OllamaBackend: Backend {
    public var baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }

    public static func requestBody(png: Data, model: String) -> [String: Any] {
        [
            "model": model,
            "stream": false,
            "keep_alive": "30m",  // mantiene el modelo en memoria: ~0.6 s en caliente vs ~6 s en frío
            "options": ["temperature": 0],
            "messages": [
                ["role": "system", "content": Prompt.system],
                ["role": "user", "content": Prompt.userText, "images": [png.base64EncodedString()]],
            ],
        ]
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

    public func solve(png: Data, model: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "api/chat"), timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try Self.requestBody(png: png, model: model).jsonData()
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CopyEzzError("Ollama no responde en :11434 (¿brew services start ollama?)")
        }
        return try Self.parseResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
