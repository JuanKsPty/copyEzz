import CopyEzzCore
import CoreGraphics
import Foundation

enum RecordingTarget: Sendable {
    case mouse, hotkey
}

enum RecordedInput: Sendable {
    case mouse(Int)
    case hotkey(Hotkey)
    case cancelled
}

/// Escucha el botón del mouse y el atajo de teclado en todo el sistema con un CGEventTap.
/// Los eventos que disparan la captura se consumen (el navegador no hace "adelante").
/// Requiere el permiso de Accesibilidad.
@MainActor
final class InputMonitor {
    var mouseButton = 4
    var hotkey = Hotkey.default
    var onTrigger: () -> Void = {}
    /// Mientras no es nil, el próximo botón (o combinación) se entrega a `onRecorded` en vez de disparar.
    var recording: RecordingTarget?
    var onRecorded: (RecordedInput) -> Void = { _ in }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: inputTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    /// Devuelve true si el evento se consume.
    fileprivate func handle(_ event: TapEvent) -> Bool {
        switch event.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false

        case .otherMouseDown, .otherMouseUp:
            if recording == .mouse, event.type == .otherMouseDown {
                recording = nil
                onRecorded(.mouse(event.button))  // actualiza `mouseButton`, así el mouseUp también se consume
                return true
            }
            guard event.button == mouseButton else { return false }
            if event.type == .otherMouseDown { trigger() }
            return true

        case .keyDown:
            if recording == .hotkey {
                let flags = event.flags.intersection(Hotkey.relevantFlags)
                if event.keyCode == 53, flags.isEmpty {  // Esc cancela
                    recording = nil
                    onRecorded(.cancelled)
                    return true
                }
                guard !flags.isEmpty else { return false }  // el atajo necesita algún modificador
                recording = nil
                onRecorded(.hotkey(Hotkey(keyCode: event.keyCode, flags: flags)))
                return true
            }
            guard hotkey.matches(keyCode: event.keyCode, flags: event.flags) else { return false }
            if !event.isRepeat { trigger() }
            return true

        default:
            return false
        }
    }

    /// Se dispara fuera del callback: macOS desactiva los event taps que tardan en responder.
    private func trigger() {
        Task { @MainActor in self.onTrigger() }
    }
}

fileprivate struct TapEvent: Sendable {
    var type: CGEventType
    var button: Int
    var keyCode: Int
    var flags: CGEventFlags
    var isRepeat: Bool
}

private func inputTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let info = TapEvent(
        type: type,
        button: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
        keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
        flags: event.flags,
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    )
    // El tap está en el run loop principal, así que el callback corre en el main thread.
    let consume = MainActor.assumeIsolated { monitor.handle(info) }
    return consume ? nil : Unmanaged.passUnretained(event)
}
