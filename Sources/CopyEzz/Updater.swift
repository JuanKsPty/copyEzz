import AppKit
import Combine
import Sparkle

/// Actualizaciones con Sparkle. Solo se activa en builds con `SUPublicEDKey` (las de `scripts/bundle.sh`).
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController?

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty, !key.hasPrefix("__") else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    var isEnabled: Bool { controller != nil }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
