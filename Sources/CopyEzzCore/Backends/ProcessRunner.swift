import Foundation

enum ProcessRunner {
    struct Output: Sendable {
        var stdout: Data
        var stderr: Data
        var status: Int32
        var timedOut: Bool
    }

    static func run(
        _ executable: URL, arguments: [String], input: Data, environment: [String: String],
        currentDirectory: URL, timeout: TimeInterval
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try runBlocking(executable, arguments: arguments, input: input, environment: environment,
                                    currentDirectory: currentDirectory, timeout: timeout)
                })
            }
        }
    }

    /// Ejecuta el proceso escribiendo stdin y leyendo stdout/stderr en paralelo (la imagen en base64 pesa
    /// varios MB: hacerlo en secuencia puede bloquear los pipes). Termina el proceso si pasa `timeout`.
    static func runBlocking(
        _ executable: URL, arguments: [String], input: Data, environment: [String: String],
        currentDirectory: URL, timeout: TimeInterval
    ) throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        let writer = stdin.fileHandleForWriting
        // Si el proceso cierra stdin antes de tiempo, que la escritura falle en vez de matar la app con SIGPIPE.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        let collected = Collected()
        let readers = DispatchGroup()
        let outHandle = stdout.fileHandleForReading, errHandle = stderr.fileHandleForReading
        DispatchQueue.global().async(group: readers) { collected.stdout = outHandle.readDataToEndOfFile() }
        DispatchQueue.global().async(group: readers) { collected.stderr = errHandle.readDataToEndOfFile() }
        DispatchQueue.global().async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            finished.wait()
        }
        readers.wait()
        return Output(stdout: collected.stdout, stderr: collected.stderr, status: process.terminationStatus, timedOut: timedOut)
    }

    /// Cada campo lo escribe un solo hilo lector y se lee después de `readers.wait()`.
    private final class Collected: @unchecked Sendable {
        var stdout = Data()
        var stderr = Data()
    }
}
