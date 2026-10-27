import CopyEzzCore
import SwiftUI

struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        let icon = state.busy ? "ellipsis.circle" : "text.viewfinder"
        if state.prefs.showAnswerInMenuBar, !state.busy, let last = state.results.last {
            Text("\(Image(systemName: icon)) \(String(last.title.prefix(40)))")
        } else {
            Image(systemName: icon)
        }
    }
}

struct MenuContent: View {
    let state: AppState
    @ObservedObject var updater: Updater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let last = state.results.last {
            Text(String(last.title.prefix(60)))
        }
        Text(state.statusLine)
        if let context = state.context {
            Text("Contexto: \(context.name)")
        }
        Divider()

        Button("Capturar ahora") { state.captureNow() }
        Button("Abrir página") { state.openPage() }
        Picker("Motor", selection: Binding(get: { state.prefs.backend }, set: { state.selectBackend($0) })) {
            ForEach(BackendKind.allCases) { backend in
                Text(backend.label).tag(backend)
            }
        }

        if !state.accessibilityGranted {
            Button("⚠︎ Permitir Accesibilidad (botón y atajo)…") { state.requestAccessibility() }
        }
        if !state.screenRecordingGranted {
            Button("⚠︎ Permitir Grabación de pantalla…") { state.requestScreenRecording() }
        }
        Divider()

        Button("Ajustes…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        if let version = updater.pendingVersion {
            Button("⬆︎ Instalar CopyEzz \(version)…") { updater.checkForUpdates() }
        } else if updater.isEnabled {
            Button("Buscar actualizaciones…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        Divider()
        Button("Salir de CopyEzz") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
