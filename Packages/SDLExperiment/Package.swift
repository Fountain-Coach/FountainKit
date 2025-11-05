// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SDLExperiment",
    platforms: [ .macOS(.v14) ],
    products: [
        .executable(name: "sdl-composer-experiment", targets: ["SDLComposerExperiment"]),
        .executable(name: "sdl-diagnostics", targets: ["SDLDiagnostics"]) 
    ],
    dependencies: [
        // Use SDLKit from GitHub rather than a local submodule
        .package(url: "https://github.com/Fountain-Coach/SDLKit.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SDLComposerExperiment",
            dependencies: [
                .product(name: "SDLKit", package: "SDLKit")
            ],
            path: "Sources/SDLComposerExperiment"
        ),
        .executableTarget(
            name: "SDLDiagnostics",
            dependencies: [
                // use C shim directly for low-level info
                .product(name: "SDLKit", package: "SDLKit")
            ],
            path: "Sources/SDLDiagnostics"
        )
    ]
)
