import AppKit
import CopyEzzCore
import Observation

/// Estado de la app: ajustes, capturas en curso y resultados. Equivale al `State` + `solve()` de legacy/copyezz.py.
@MainActor @Observable
final class AppState {
    var prefs = Preferences.load() {
        didSet { preferencesChanged(from: oldValue) }
    }

    private(set) var busy = false
    private(set) var results: [SolveResult] = []
    private(set) var serverError: String?
    private(set) var accessibilityGranted = Permissions.accessibility
    private(set) var screenRecordingGranted = Permissions.screenRecording
    private(set) var recordingTarget: RecordingTarget?

    @ObservationIgnored private var seq = 0
    @ObservationIgnored private let server = LocalServer(indexHTML: AppState.loadIndexHTML())
    @ObservationIgnored private let input = InputMonitor()
    @ObservationIgnored private let capturer = ScreenCapturer()
    @ObservationIgnored private let history = HistoryLog()
    @ObservationIgnored private var permissionTimer: Timer?

    var pageURL: URL { URL(string: "http://127.0.0.1:\(prefs.port)")! }

    var backendConfig: BackendConfig {
        BackendConfig(backend: prefs.backend.rawValue, model: prefs.model, backends: BackendKind.defaultModels)
    }

    var statusLine: String {
        if let serverError { return "⚠︎ " + serverError }
        return (busy ? "Pensando…" : "Listo") + " · \(prefs.backend.rawValue) (\(prefs.model))"
    }

    // MARK: - Arranque

    func start() {
        input.mouseButton = prefs.mouseButton
        input.hotkey = prefs.hotkey
        input.onTrigger = { [weak self] in self?.solve(png: nil) }
        input.onRecorded = { [weak self] recorded in self?.finishRecording(recorded) }

        startServer()
        if !accessibilityGranted { Permissions.requestAccessibility() }
        refreshPermissions()
        // Los permisos se conceden en Ajustes del Sistema mientras la app corre: se revisan cada 2 s.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        if prefs.openPageOnLaunch, serverError == nil { openPage() }
    }

    private func startServer() {
        server.stop()
        serverError = nil
        guard let port = UInt16(exactly: prefs.port), port > 0 else {
            serverError = "puerto inválido: \(prefs.port)"
            return
        }
        let handlers = LocalServer.Handlers(
            hello: { [weak self] in
                guard let self else { return .thinking(id: 0) }
                return .hello(self.backendConfig, busy: self.busy, results: self.results)
            },
            solve: { [weak self] png in self?.solve(png: png) },
            config: { [weak self] backend, model in self?.applyConfig(backend: backend, model: model) },
            failed: { [weak self] message in self?.serverError = message }
        )
        do {
            try server.start(port: port, handlers: handlers)
        } catch {
            serverError = "no se pudo abrir el puerto \(port)"
        }
    }

    private func refreshPermissions() {
        accessibilityGranted = Permissions.accessibility
        screenRecordingGranted = Permissions.screenRecording
        if accessibilityGranted, !input.isRunning {
            _ = input.start()
        }
    }

    private func preferencesChanged(from old: Preferences) {
        prefs.save()
        input.mouseButton = prefs.mouseButton
        input.hotkey = prefs.hotkey
        if prefs.backend != old.backend || prefs.model != old.model {
            server.publish(.config(backendConfig))
        }
        if prefs.port != old.port {
            startServer()
        }
    }

    // MARK: - Acciones

    func captureNow() {
        // Deja que el menú termine de cerrarse para que no salga en la captura.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            solve(png: nil)
        }
    }

    func openPage() {
        NSWorkspace.shared.open(pageURL)
    }

    func selectBackend(_ backend: BackendKind) {
        guard backend != prefs.backend else { return }
        prefs.backend = backend
        prefs.model = backend.defaultModel
    }

    /// `POST /config` desde la página: cambia de motor y modelo (vacío = el del motor).
    private func applyConfig(backend raw: String, model: String?) -> BackendConfig? {
        guard let backend = BackendKind(rawValue: raw) else { return nil }
        let trimmed = model?.trimmingCharacters(in: .whitespaces) ?? ""
        prefs.backend = backend
        prefs.model = trimmed.isEmpty ? backend.defaultModel : trimmed
        return backendConfig
    }

    func requestAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openSettings(.accessibility)
    }

    func requestScreenRecording() {
        Permissions.requestScreenRecording()
        Permissions.openSettings(.screenRecording)
    }

    func startRecording(_ target: RecordingTarget) {
        recordingTarget = target
        input.recording = target
    }

    private func finishRecording(_ recorded: RecordedInput) {
        recordingTarget = nil
        switch recorded {
        case let .mouse(button): prefs.mouseButton = button
        case let .hotkey(hotkey): prefs.hotkey = hotkey
        case .cancelled: break
        }
    }

    // MARK: - Resolver

    /// Captura (o usa el PNG recibido), consulta el motor y publica el resultado.
    /// Solo la petición más reciente actualiza la página: las anteriores en vuelo quedan reemplazadas.
    func solve(png: Data?) {
        seq += 1
        let id = seq
        let backend = prefs.backend, model = prefs.model
        busy = true
        server.publish(.thinking(id: id))

        Task {
            let started = ContinuousClock.now
            var result = SolveResult(type: .answer, id: id, ts: Date().timeIntervalSince1970,
                                     backend: backend.rawValue, model: model, ms: 0)
            do {
                let image = if let png { try PNGImage.downscaled(png) } else { try await capturer.captureDisplayUnderMouse() }
                let text = try await makeBackend(backend).solve(png: image, model: model)
                let parts = AnswerParser.split(text)
                result.answer = parts.answer
                result.detail = parts.detail
            } catch {
                result.type = .error
                result.error = (error as? CopyEzzError)?.message ?? error.localizedDescription
            }
            result.ms = Int((ContinuousClock.now - started) / .milliseconds(1))
            finish(result)
        }
    }

    private func finish(_ result: SolveResult) {
        try? history.append(result)
        guard result.id == seq else { return }
        busy = false
        results.append(result)
        if results.count > 50 { results.removeFirst(results.count - 50) }
        server.publish(.result(result))
    }

    private func makeBackend(_ kind: BackendKind) throws -> any Backend {
        switch kind {
        case .claudeCode:
            guard let executable = ClaudeCodeBackend.locate(preferred: prefs.claudePath) else {
                throw CopyEzzError("no se encontró `claude` (configura la ruta en Ajustes)")
            }
            return ClaudeCodeBackend(executable: executable)
        case .api:
            let environment = ProcessInfo.processInfo.environment
            let apiKey = Keychain.apiKey ?? environment["ANTHROPIC_API_KEY"]
            // Solo para pruebas contra un servidor falso.
            let baseURL = environment["COPYEZZ_API_BASE_URL"].flatMap(URL.init(string:))
            return AnthropicAPIBackend(apiKey: apiKey, baseURL: baseURL ?? URL(string: "https://api.anthropic.com")!)
        case .ollama:
            return OllamaBackend()
        }
    }

    private static func loadIndexHTML() -> Data {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html"),
              let data = try? Data(contentsOf: url)
        else { return Data("<!doctype html><title>copyEzz</title><p>Falta index.html en el bundle.</p>".utf8) }
        return data
    }
}
