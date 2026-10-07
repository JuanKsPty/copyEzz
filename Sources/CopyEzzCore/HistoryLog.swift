import Foundation

/// Registro de cada respuesta, una línea JSON por captura.
public struct HistoryLog: Sendable {
    public let url: URL

    public init(url: URL = HistoryLog.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "CopyEzz/history.jsonl")
    }

    public func append(_ result: SolveResult) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = try encoder.encode(result) + Data("\n".utf8)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            try line.write(to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
