import AppKit
import ApplicationServices
import Security
import ServiceManagement

/// Permisos de Accesibilidad (atajo y botón del mouse) y Grabación de pantalla (captura).
enum Permissions {
    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
    }

    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Muestra el aviso del sistema (solo la primera vez).
    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSettings(_ pane: Pane) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!)
    }
}

/// API key de Anthropic guardada en el Llavero.
enum Keychain {
    private static let service = "io.github.juankspty.copyezz"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        get {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
            else { return nil }
            return key
        }
        set {
            let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
            SecItemDelete(base as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var item = base
            item[kSecValueData] = Data(newValue.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

/// "Abrir al iniciar sesión" con SMAppService.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
