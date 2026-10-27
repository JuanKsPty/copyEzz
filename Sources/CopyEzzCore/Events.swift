import Foundation

/// Resultado de una captura, con la misma forma JSON que usa `Resources/index.html`.
public struct SolveResult: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case answer, error
    }

    public var type: Kind
    public var id: Int
    public var ts: Double
    public var backend: String
    public var model: String
    public var answer: String?
    public var detail: String?
    public var error: String?
    /// Nombre del archivo de contexto con el que se respondió, si había uno.
    public var context: String?
    public var ms: Int

    public init(
        type: Kind, id: Int, ts: Double, backend: String, model: String,
        answer: String? = nil, detail: String? = nil, error: String? = nil, context: String? = nil, ms: Int
    ) {
        self.type = type
        self.id = id
        self.ts = ts
        self.backend = backend
        self.model = model
        self.answer = answer
        self.detail = detail
        self.error = error
        self.context = context
        self.ms = ms
    }

    /// Lo que va en el título de la pestaña y en la barra de menú.
    public var title: String {
        type == .answer ? (answer ?? "") : "⚠ " + (error ?? "")
    }
}

/// Motor activo y modelos por defecto de cada motor.
public struct BackendConfig: Codable, Equatable, Sendable {
    public var backend: String
    public var model: String
    public var backends: [String: String]

    public init(backend: String, model: String, backends: [String: String]) {
        self.backend = backend
        self.model = model
        self.backends = backends
    }
}

/// Eventos SSE de `/events` (contrato de la versión Python, más el contexto).
public enum ServerEvent: Sendable {
    case hello(BackendConfig, busy: Bool, results: [SolveResult], context: QuizContext.Info?)
    case config(BackendConfig)
    case thinking(id: Int)
    case result(SolveResult)
    /// Se cargó o se quitó el archivo de contexto (`nil`).
    case context(QuizContext.Info?)

    public func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data?
        switch self {
        case let .hello(config, busy, results, context):
            data = try? encoder.encode(Hello(type: "hello", backend: config.backend, model: config.model,
                                             backends: config.backends, busy: busy, results: results, context: context))
        case let .config(config):
            data = try? encoder.encode(Config(type: "config", backend: config.backend, model: config.model,
                                              backends: config.backends))
        case let .thinking(id):
            data = try? encoder.encode(Thinking(type: "thinking", id: id))
        case let .result(result):
            data = try? encoder.encode(result)
        case let .context(context):
            data = try? encoder.encode(Context(type: "context", context: context))
        }
        return data ?? Data("{}".utf8)
    }

    /// Cuadro SSE listo para enviar: `data: {...}\n\n`.
    public func sseFrame() -> Data {
        Data("data: ".utf8) + json() + Data("\n\n".utf8)
    }

    private struct Hello: Encodable {
        let type, backend, model: String
        let backends: [String: String]
        let busy: Bool
        let results: [SolveResult]
        let context: QuizContext.Info?
    }

    private struct Config: Encodable {
        let type, backend, model: String
        let backends: [String: String]
    }

    private struct Thinking: Encodable {
        let type: String
        let id: Int
    }

    private struct Context: Encodable {
        let type: String
        let context: QuizContext.Info?
    }
}
