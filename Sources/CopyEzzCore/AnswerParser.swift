import Foundation

public enum AnswerParser {
    /// Separa la respuesta del modelo: la primera línea va al título y el resto es la justificación.
    public static func split(_ text: String) -> (answer: String, detail: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let answer = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let detail = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (answer.isEmpty ? "(vacío)" : answer, detail)
    }
}
