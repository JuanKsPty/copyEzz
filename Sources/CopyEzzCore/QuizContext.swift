import Foundation

/// Material de referencia que el usuario sube como .txt (apuntes, banco de preguntas, temario).
/// Va en el system prompt de cada captura para que el modelo responda con él.
public struct QuizContext: Codable, Equatable, Sendable {
    /// Unos 250 mil tokens: cabe en la ventana de los modelos actuales y frena archivos equivocados.
    public static let maxBytes = 1024 * 1024

    public var name: String
    public var text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }

    /// Valida y decodifica un archivo subido (UTF-8, UTF-16 con BOM o Windows-1252).
    public init(name: String, data: Data) throws {
        guard data.count <= Self.maxBytes else { throw CopyEzzError("el archivo de contexto pasa de 1 MB") }
        let text = try Self.decode(data)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CopyEzzError("el archivo de contexto está vacío") }
        let base = (name as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(name: base.isEmpty ? "contexto.txt" : String(base.prefix(120)), text: text)
    }

    /// Lo que ven la página y Ajustes, sin el texto.
    public var info: Info { Info(name: name, size: text.utf8.count) }

    public struct Info: Codable, Equatable, Sendable {
        public var name: String
        /// Bytes del texto en UTF-8.
        public var size: Int
    }

    private static func decode(_ data: Data) throws -> String {
        // Notepad de Windows guarda "Unicode" como UTF-16 con BOM.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        // Un PDF o un .docx renombrado a .txt trae bytes nulos.
        guard !data.contains(0) else { throw CopyEzzError("el contexto no parece un archivo de texto") }
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        // Archivos viejos de Windows en español: "canción" en Windows-1252 no es UTF-8 válido.
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }
}

/// Guarda el contexto entre sesiones, junto al historial.
public struct ContextStore: Sendable {
    public let url: URL

    public init(url: URL = ContextStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "CopyEzz/context.json")
    }

    public func load() -> QuizContext? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QuizContext.self, from: data)
    }

    public func save(_ context: QuizContext) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(context).write(to: url, options: .atomic)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
