import CopyEzzCore
import Foundation

/// Ajustes persistidos en UserDefaults (como un JSON, para agregar campos sin migraciones).
struct Preferences: Codable, Equatable {
    var backend = BackendKind.claudeCode
    var model = BackendKind.claudeCode.defaultModel
    var claudePath = ""
    /// Número de botón de macOS: 2 = rueda, 3 = lateral "atrás", 4 = lateral "adelante".
    var mouseButton = 4
    var hotkey = Hotkey.default
    var port = 8765
    var openPageOnLaunch = true
    var showAnswerInMenuBar = false

    init() {}

    // Campos que falten (versiones anteriores) toman su valor por defecto.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Preferences()
        backend = (try? container.decode(BackendKind.self, forKey: .backend)) ?? fallback.backend
        model = (try? container.decode(String.self, forKey: .model)) ?? fallback.model
        claudePath = (try? container.decode(String.self, forKey: .claudePath)) ?? fallback.claudePath
        mouseButton = (try? container.decode(Int.self, forKey: .mouseButton)) ?? fallback.mouseButton
        hotkey = (try? container.decode(Hotkey.self, forKey: .hotkey)) ?? fallback.hotkey
        port = (try? container.decode(Int.self, forKey: .port)) ?? fallback.port
        openPageOnLaunch = (try? container.decode(Bool.self, forKey: .openPageOnLaunch)) ?? fallback.openPageOnLaunch
        showAnswerInMenuBar = (try? container.decode(Bool.self, forKey: .showAnswerInMenuBar)) ?? fallback.showAnswerInMenuBar
    }

    private static let key = "preferences"

    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return preferences
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }

    static func mouseButtonName(_ number: Int) -> String {
        switch number {
        case 2: "botón 2 (rueda)"
        case 3: "botón 3 (lateral atrás)"
        case 4: "botón 4 (lateral adelante)"
        default: "botón \(number)"
        }
    }
}
