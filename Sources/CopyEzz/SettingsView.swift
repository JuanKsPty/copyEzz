import CopyEzzCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var apiKey = Keychain.apiKey ?? ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var detectedClaude = ClaudeCodeBackend.locate()?.path
    @State private var choosingContext = false
    @State private var contextError: String?

    var body: some View {
        Form {
            Section("Motor") {
                Picker("Motor", selection: Binding(get: { state.prefs.backend }, set: { state.selectBackend($0) })) {
                    ForEach(BackendKind.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
                TextField("Modelo", text: $state.prefs.model, prompt: Text(state.prefs.backend.defaultModel))
                switch state.prefs.backend {
                case .claudeCode:
                    TextField("Ruta de claude", text: $state.prefs.claudePath, prompt: Text(detectedClaude ?? "no encontrado"))
                    Text("Usa el `claude` de tu terminal con tu sesión y tu suscripción. Déjalo vacío para detectarlo solo.")
                        .font(.caption).foregroundStyle(.secondary)
                case .api:
                    SecureField("API key", text: $apiKey, prompt: Text("sk-ant-…"))
                        .onChange(of: apiKey) { _, newValue in Keychain.apiKey = newValue }
                    Text("Se guarda en el Llavero de macOS.").font(.caption).foregroundStyle(.secondary)
                case .ollama:
                    Text("Requiere Ollama en 127.0.0.1:11434 con el modelo descargado (`ollama pull \(state.prefs.model)`).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Contexto") {
                LabeledContent("Archivo") {
                    HStack {
                        if let info = state.context?.info {
                            Text("\(info.name) · \(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file))")
                                .lineLimit(1).truncationMode(.middle)
                        } else {
                            Text("ninguno").foregroundStyle(.secondary)
                        }
                        Button("Elegir…") { choosingContext = true }
                        if state.context != nil {
                            Button("Quitar") { state.clearContext() }
                        }
                    }
                }
                Text("Apuntes o banco de preguntas en .txt (máx. 1 MB). Se envía con cada captura y el modelo responde con ese material.")
                    .font(.caption).foregroundStyle(.secondary)
                if let contextError {
                    Text(contextError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Disparo") {
                LabeledContent("Botón del mouse") {
                    recordButton(
                        current: Preferences.mouseButtonName(state.prefs.mouseButton),
                        target: .mouse, prompt: "Presiona el botón…"
                    )
                }
                LabeledContent("Atajo de teclado") {
                    recordButton(current: state.prefs.hotkey.display, target: .hotkey, prompt: "Presiona el atajo… (Esc cancela)")
                }
                if !state.accessibilityGranted {
                    Text("Necesita el permiso de Accesibilidad.").font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Página") {
                LabeledContent("Dirección") {
                    Link(state.pageURL.absoluteString, destination: state.pageURL)
                }
                TextField("Puerto", value: $state.prefs.port, format: .number.grouping(.never))
                Toggle("Abrir la página al iniciar", isOn: $state.prefs.openPageOnLaunch)
                Toggle("Mostrar la respuesta también en la barra de menú", isOn: $state.prefs.showAnswerInMenuBar)
                if let error = state.serverError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Sistema") {
                Toggle("Abrir CopyEzz al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.set(enabled)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                permissionRow("Accesibilidad", granted: state.accessibilityGranted) { state.requestAccessibility() }
                permissionRow("Grabación de pantalla", granted: state.screenRecordingGranted) { state.requestScreenRecording() }
                LabeledContent("Versión", value: AppInfo.version)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingContext, allowedContentTypes: [.plainText]) { result in
            loadContext(result)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func loadContext(_ result: Result<URL, Error>) {
        contextError = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try state.setContext(name: url.lastPathComponent, data: Data(contentsOf: url))
        } catch {
            contextError = (error as? CopyEzzError)?.message ?? "no se pudo leer el archivo"
        }
    }

    private func recordButton(current: String, target: RecordingTarget, prompt: String) -> some View {
        HStack {
            Text(state.recordingTarget == target ? prompt : current)
                .foregroundStyle(state.recordingTarget == target ? .orange : .primary)
            Button("Cambiar") { state.startRecording(target) }
                .disabled(!state.accessibilityGranted || state.recordingTarget != nil)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, request: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if granted {
                Label("Concedido", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Permitir…", action: request)
            }
        }
    }
}
