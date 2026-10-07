import Foundation

/// Error con un mensaje corto en español, pensado para mostrarse tal cual en el título de la pestaña.
public struct CopyEzzError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
