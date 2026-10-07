import AppKit
import Combine
import Sparkle

/// Actualizaciones con Sparkle. Solo se activa en builds con `SUPublicEDKey` (las de `scripts/bundle.sh`).
/// Como app de barra de menú usa "recordatorios discretos": las comprobaciones automáticas no abren una
/// ventana en medio de otra cosa, sino que dejan un aviso en el menú.
@MainActor
final class Updater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    /// Versión encontrada por una comprobación automática y aún no mostrada.
    @Published private(set) var pendingVersion: String?
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty, !key.hasPrefix("__") else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    var isEnabled: Bool { controller != nil }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Solo se muestra la ventana si la comprobación ocurrió justo al abrir la app.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate, !state.userInitiated {
            pendingVersion = update.displayVersionString
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
    }
}
