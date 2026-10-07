// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyEzz",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // Lógica pura (HTTP, eventos, motores, imágenes): se prueba con `swift test`.
        .target(name: "CopyEzzCore"),
        .executableTarget(
            name: "CopyEzz",
            dependencies: [
                "CopyEzzCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // Sparkle.framework vive en CopyEzz.app/Contents/Frameworks (lo copia scripts/bundle.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "CopyEzzCoreTests", dependencies: ["CopyEzzCore"]),
    ]
)
