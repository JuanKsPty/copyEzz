import CopyEzzCore
import Foundation
import Network

/// Server HTTP mínimo en 127.0.0.1 con el mismo contrato que legacy/copyezz.py:
/// `GET /`, `GET /events` (SSE), `POST /solve` y `POST /config`; más `POST`/`DELETE /context`.
/// Todo su estado vive en `queue`; la app se comunica con él solo mediante `Handlers` y `publish`.
final class LocalServer: @unchecked Sendable {
    struct Handlers: Sendable {
        var hello: @MainActor @Sendable () -> ServerEvent
        var solve: @MainActor @Sendable (Data?) -> Void
        var config: @MainActor @Sendable (_ backend: String, _ model: String?) -> BackendConfig?
        var setContext: @MainActor @Sendable (_ name: String, _ data: Data) throws -> Void
        var clearContext: @MainActor @Sendable () -> Void
        var failed: @MainActor @Sendable (String) -> Void
    }

    private let queue = DispatchQueue(label: "io.github.juankspty.copyezz.server")
    private let indexHTML: Data
    private var listener: NWListener?
    private var handlers: Handlers?
    private var port: UInt16 = 0
    private var streams: [ObjectIdentifier: NWConnection] = [:]
    private var pingTimer: DispatchSourceTimer?

    init(indexHTML: Data) {
        self.indexHTML = indexHTML
    }

    func start(port: UInt16, handlers: Handlers) throws {
        let parameters = NWParameters.tcp
        // Solo loopback: nadie de la red puede conectarse (y macOS no pide permiso de red local).
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            guard case let .failed(error) = state else { return }
            let message = error == .posix(.EADDRINUSE) ? "el puerto \(port) está ocupado" : "server: \(error)"
            Task { @MainActor in handlers.failed(message) }
            self?.stop()
        }

        queue.sync {
            self.port = port
            self.handlers = handlers
            self.listener = listener
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 15, repeating: 15)
            timer.setEventHandler { [weak self] in self?.broadcast(HTTPResponse.ping) }
            timer.resume()
            pingTimer = timer
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            pingTimer?.cancel()
            pingTimer = nil
            for connection in streams.values { close(connection) }
            streams = [:]
        }
    }

    /// Envía un evento a todas las páginas conectadas. Se llama desde el main actor, igual que `hello`,
    /// así los eventos llegan en el mismo orden en que ocurrieron.
    func publish(_ event: ServerEvent) {
        let frame = event.sseFrame()
        queue.async { self.broadcast(frame) }
    }

    // MARK: - Conexiones (en `queue`)

    private func broadcast(_ data: Data) {
        for connection in streams.values { send(data, on: connection) }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, receiveError in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            do {
                if let request = try HTTPParser.parse(buffer) {
                    return self.route(request, on: connection)
                }
            } catch {
                let status = (error as? HTTPParser.Failure) == .tooLarge ? 413 : 400
                return self.respond(HTTPResponse.text(status, "bad request"), on: connection)
            }
            if isComplete || receiveError != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        guard let handlers,
              HTTPGuard.isAllowed(host: request.header("host"), origin: request.header("origin"), port: port)
        else { return respond(HTTPResponse.text(403, "forbidden"), on: connection) }

        switch (request.method, request.path) {
        case ("GET", "/"):
            respond(HTTPResponse.make(status: 200, body: indexHTML, contentType: "text/html; charset=utf-8"), on: connection)
        case ("GET", "/events"):
            openStream(connection, handlers: handlers)
        case ("POST", "/solve"):
            let png = request.body.isEmpty ? nil : request.body  // sin body: la app captura la pantalla
            Task { @MainActor in handlers.solve(png) }
            respond(HTTPResponse.text(202, "ok"), on: connection)
        case ("POST", "/config"):
            let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            guard let backend = json?["backend"] as? String else {
                return respond(HTTPResponse.text(400, "backend invalido"), on: connection)
            }
            let model = json?["model"] as? String
            Task { @MainActor in
                let response = handlers.config(backend, model).map {
                    HTTPResponse.make(status: 200, body: ServerEvent.config($0).json(), contentType: "application/json")
                } ?? HTTPResponse.text(400, "backend invalido")
                self.queue.async { self.respond(response, on: connection) }
            }
        case ("POST", "/context"):
            // Cuerpo: el .txt tal cual. El nombre llega con encodeURIComponent porque puede tener tildes.
            let name = request.header("x-filename")?.removingPercentEncoding ?? ""
            Task { @MainActor in
                let response: Data
                do {
                    try handlers.setContext(name, request.body)
                    response = HTTPResponse.text(200, "ok")
                } catch {
                    response = HTTPResponse.text(400, (error as? CopyEzzError)?.message ?? "no se pudo cargar el contexto")
                }
                self.queue.async { self.respond(response, on: connection) }
            }
        case ("DELETE", "/context"):
            Task { @MainActor in handlers.clearContext() }
            respond(HTTPResponse.text(200, "ok"), on: connection)
        default:
            respond(HTTPResponse.text(404, "not found"), on: connection)
        }
    }

    private func openStream(_ connection: NWConnection, handlers: Handlers) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close(connection)
            default: break
            }
        }
        send(HTTPResponse.eventStreamHead, on: connection)
        Task { @MainActor in
            let hello = handlers.hello()
            self.queue.async {
                self.streams[ObjectIdentifier(connection)] = connection
                self.send(hello.sseFrame(), on: connection)
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.close(connection) }
        })
    }

    private func respond(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func close(_ connection: NWConnection) {
        streams[ObjectIdentifier(connection)] = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
