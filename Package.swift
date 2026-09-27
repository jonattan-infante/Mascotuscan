// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mascotuscan",
    platforms: [.macOS(.v13)],
    targets: [
        // Toda la logica vive en la libreria para que los tests puedan importarla.
        // El ejecutable no puede testearse directamente: tiene codigo top-level.
        .target(name: "MascoTuscanKit", path: "Sources/MascoTuscanKit"),
        // App de AppKit sin bundle: se registra como .accessory, sin icono en el Dock.
        .executableTarget(
            name: "mascotuscan",
            dependencies: ["MascoTuscanKit"],
            path: "Sources/mascotuscan"
        ),
        // Cubre solo logica pura: parseo, validacion y formateo. Lo que depende
        // de pantalla se verifica con `make render`.
        .testTarget(
            name: "MascoTuscanKitTests",
            dependencies: ["MascoTuscanKit"],
            path: "Tests/MascoTuscanKitTests"
        ),
    ],
    // Modo Swift 5 a proposito: el codigo usa closures que capturan estado del
    // main actor sin anotar, y migrar a la concurrencia estricta de Swift 6 es
    // trabajo aparte (ver EXECUTION-PLAN, backlog).
    swiftLanguageVersions: [.v5]
)
