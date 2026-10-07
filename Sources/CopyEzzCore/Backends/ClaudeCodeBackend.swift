import Foundation

/// Claude Code headless (`claude -p`): usa la suscripción del usuario, sin API key.
public struct ClaudeCodeBackend: Backend {
    public var executable: URL
    public var timeout: TimeInterval

    public init(executable: URL, timeout: TimeInterval = 120) {
        self.executable = executable
        self.timeout = timeout
    }

    public static func arguments(model: String) -> [String] {
        [
            "-p",
            "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--model", model,
            "--system-prompt", Prompt.system,
            // Sin herramientas, MCP, sesión guardada ni hooks: solo una respuesta, y arranque más rápido.
            "--tools", "", "--strict-mcp-config", "--no-session-persistence", "--setting-sources", "",
        ]
    }

    /// Una línea stream-json con el mensaje del usuario (imagen + texto).
    public static func stdinLine(png: Data) throws -> Data {
        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": MessageContent.imageAndText(png: png)],
        ]
        return try message.jsonData() + Data("\n".utf8)
    }

    /// Toma el último evento `{"type": "result"}` de la salida stream-json.
    public static func parseResult(stdout: String, stderr: String, status: Int32) throws -> String {
        for line in stdout.split(separator: "\n").reversed() {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  event["type"] as? String == "result"
            else { continue }
            if event["is_error"] as? Bool == true {
                throw CopyEzzError(event["result"] as? String ?? "claude devolvió un error")
            }
            if let result = event["result"] as? String { return result }
        }
        let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300)
        throw CopyEzzError(tail.isEmpty ? "claude salió con código \(status)" : String(tail))
    }

    public func solve(png: Data, model: String) async throws -> String {
        var environment = ProcessInfo.processInfo.environment
        // Las apps abiertas al iniciar sesión no heredan el PATH de la terminal.
        let extraPaths = [executable.deletingLastPathComponent().path] + Self.searchDirectories
        environment["PATH"] = (extraPaths + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")

        let output: ProcessRunner.Output
        do {
            output = try await ProcessRunner.run(
                executable, arguments: Self.arguments(model: model), input: Self.stdinLine(png: png),
                environment: environment, currentDirectory: FileManager.default.temporaryDirectory, timeout: timeout
            )
        } catch {
            throw CopyEzzError("no se pudo ejecutar \(executable.path)")
        }
        if output.timedOut { throw CopyEzzError("claude tardó más de \(Int(timeout)) s") }
        return try Self.parseResult(
            stdout: String(decoding: output.stdout, as: UTF8.self),
            stderr: String(decoding: output.stderr, as: UTF8.self),
            status: output.status
        )
    }

    // MARK: - Ubicar `claude`

    static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.claude/local"]
    }

    /// Ruta de `claude`: la configurada si es ejecutable, si no las ubicaciones habituales y, como último
    /// recurso, la que resuelva una shell de login del usuario.
    public static func locate(preferred: String? = nil) -> URL? {
        let fileManager = FileManager.default
        if let preferred, !preferred.isEmpty {
            let path = (preferred as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: path) { return URL(filePath: path) }
        }
        for directory in searchDirectories {
            let path = directory + "/claude"
            if fileManager.isExecutableFile(atPath: path) { return URL(filePath: path) }
        }
        guard let output = try? ProcessRunner.runBlocking(
            URL(filePath: "/bin/zsh"), arguments: ["-lic", "command -v claude"], input: Data(),
            environment: ProcessInfo.processInfo.environment, currentDirectory: fileManager.temporaryDirectory, timeout: 5
        ) else { return nil }
        let path = String(decoding: output.stdout, as: UTF8.self)
            .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return path.hasPrefix("/") && fileManager.isExecutableFile(atPath: path) ? URL(filePath: path) : nil
    }
}
