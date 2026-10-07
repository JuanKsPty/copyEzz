import SwiftUI

@main
struct CopyEzzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: appDelegate.state, updater: appDelegate.updater)
        } label: {
            MenuBarLabel(state: appDelegate.state)
        }

        Settings {
            SettingsView(state: appDelegate.state)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
    }
}
