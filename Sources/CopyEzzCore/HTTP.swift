import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    /// Ruta sin query string.
    public var path: String
    /// Encabezados con el nombre en minúsculas.
    public var headers: [String: String]
    public var body: Data

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public enum HTTPParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 30 * 1024 * 1024  // una captura PNG cabe holgada

    public enum Failure: Error, Equatable {
        case malformed, tooLarge
    }

    /// Interpreta una petición HTTP/1.1 completa. Devuelve `nil` si aún faltan bytes por llegar.
    public static func parse(_ buffer: Data) throws(Failure) -> HTTPRequest? {
        guard let headerEnd = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > maxHeaderBytes { throw .tooLarge }
            return nil
        }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            throw .malformed
        }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/") else { throw .malformed }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw .malformed }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { throw .malformed }
        guard length <= maxBodyBytes else { throw .tooLarge }
        let bodyStart = headerEnd.upperBound
        guard buffer.endIndex - bodyStart >= length else { return nil }

        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return HTTPRequest(
            method: String(requestLine[0]),
            path: path,
            headers: headers,
            body: Data(buffer[bodyStart..<bodyStart + length])
        )
    }
}

public enum HTTPResponse {
    private static let reasons = [
        200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden",
        404: "Not Found", 413: "Payload Too Large", 500: "Internal Server Error",
    ]

    public static func make(status: Int, body: Data, contentType: String = "text/plain; charset=utf-8") -> Data {
        let head = "HTTP/1.1 \(status) \(reasons[status] ?? "Status")\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    public static func text(_ status: Int, _ text: String) -> Data {
        make(status: status, body: Data(text.utf8))
    }

    /// Encabezado de la conexión SSE de `/events`; después se envían cuadros `data: …\n\n`.
    public static let eventStreamHead = Data((
        "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: keep-alive\r\n\r\n"
    ).utf8)

    public static let ping = Data(": ping\n\n".utf8)
}

public enum HTTPGuard {
    /// Solo se aceptan peticiones dirigidas a este localhost: bloquea DNS rebinding (Host)
    /// y POSTs desde otras páginas (Origin). curl y la app no envían Origin.
    public static func isAllowed(host: String?, origin: String?, port: UInt16) -> Bool {
        let allowed: Set<String> = ["127.0.0.1:\(port)", "localhost:\(port)"]
        guard let host, allowed.contains(host) else { return false }
        guard let origin else { return true }
        let bare = origin.hasPrefix("http://") ? String(origin.dropFirst("http://".count)) : origin
        return allowed.contains(bare)
    }
}
