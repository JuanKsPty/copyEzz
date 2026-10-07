import AppKit
import CopyEzzCore
import ScreenCaptureKit

/// Captura la pantalla donde está el mouse, ya reducida a `CaptureSizing.maxEdge`.
struct ScreenCapturer: Sendable {
    func captureDisplayUnderMouse() async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else {
            Permissions.requestScreenRecording()
            throw CopyEzzError("falta permiso de Grabación de pantalla")
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CopyEzzError("falta permiso de Grabación de pantalla")
        }

        let target = await MainActor.run { () -> (displayID: CGDirectDisplayID?, scale: CGFloat) in
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return (number?.uint32Value, screen?.backingScaleFactor ?? 2)
        }
        guard let display = content.displays.first(where: { $0.displayID == target.displayID }) ?? content.displays.first else {
            throw CopyEzzError("no se encontró ninguna pantalla")
        }

        // Sin las ventanas propias (por ejemplo, Ajustes abierto).
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let size = CaptureSizing.scaled(
            width: Int(CGFloat(display.width) * target.scale),
            height: Int(CGFloat(display.height) * target.scale)
        )
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return try PNGImage.encode(image)
    }
}
