import Foundation

/// Un motor recibe el PNG de la captura y devuelve el texto del modelo (dos líneas, ver `Prompt`).
public protocol Backend: Sendable {
    func solve(png: Data, model: String) async throws -> String
}

public enum BackendKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case api
    case ollama

    public var id: String { rawValue }

    public var defaultModel: String {
        switch self {
        case .claudeCode: "sonnet"
        case .api: "claude-opus-5-5"
        case .ollama: "qwen2.5vl:7b"
        }
    }

    public var label: String {
        switch self {
        case .claudeCode: "Claude Code (suscripción)"
        case .api: "API de Anthropic"
        case .ollama: "Ollama (local)"
        }
    }

    public static var defaultModels: [String: String] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0.defaultModel) })
    }
}

enum MessageContent {
    /// Bloque de imagen + texto en el formato de la API de mensajes (lo usan claude-code y la API).
    static func imageAndText(png: Data) -> [[String: Any]] {
        [
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]],
            ["type": "text", "text": Prompt.userText],
        ]
    }
}

extension Dictionary where Key == String, Value == Any {
    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: self, options: [.withoutEscapingSlashes])
    }
}
