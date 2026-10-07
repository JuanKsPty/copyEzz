import CoreGraphics

/// Atajo de teclado global: código de tecla virtual + modificadores (⌃⌥⇧⌘).
public struct Hotkey: Codable, Equatable, Sendable {
    public static let relevantFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    /// ⌃⌥⌘A, el mismo de la versión Hammerspoon.
    public static let `default` = Hotkey(keyCode: 0, flags: [.maskControl, .maskAlternate, .maskCommand])

    public var keyCode: Int
    public var modifiers: UInt64

    public init(keyCode: Int, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Self.relevantFlags).rawValue
    }

    public var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    public func matches(keyCode: Int, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.relevantFlags) == self.flags
    }

    /// Ej.: "⌃⌥⌘A".
    public var display: String {
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "tecla \(keyCode)")
    }

    /// Nombres de las teclas del teclado ANSI (códigos virtuales de Carbon `kVK_*`).
    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        45: "N", 46: "M", 36: "↩", 48: "⇥", 49: "Espacio", 51: "⌫", 53: "⎋",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
