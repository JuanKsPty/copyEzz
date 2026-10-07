import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PNGImage {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    public static func isPNG(_ data: Data) -> Bool {
        data.starts(with: signature)
    }

    /// Ancho y alto leídos del encabezado IHDR, sin decodificar la imagen.
    public static func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard isPNG(data), data.count >= 24 else { return nil }
        let bytes = [UInt8](data.prefix(24))
        let width = bytes[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = bytes[20..<24].reduce(0) { $0 << 8 | Int($1) }
        return (width, height)
    }

    public static func encode(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw CopyEzzError("no se pudo codificar la captura")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CopyEzzError("no se pudo codificar la captura")
        }
        return output as Data
    }

    /// Reduce un PNG recibido por `/solve` para que su lado mayor no pase de `maxEdge`.
    public static func downscaled(_ data: Data, maxEdge: Int = CaptureSizing.maxEdge) throws -> Data {
        guard let size = pixelSize(data) else { throw CopyEzzError("la imagen recibida no es PNG") }
        guard max(size.width, size.height) > maxEdge else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw CopyEzzError("no se pudo leer la imagen recibida") }
        return try encode(image)
    }
}
