// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SDLExperiment",
    platforms: [ .macOS(.v14) ],
    products: [
        .executable(name: "sdl-composer-experiment", targets: ["SDLComposerExperiment"]) 
    ],
    dependencies: [
        // Local external dependency: initialize with
        //   git submodule update --init --recursive External/SDLKit
        .package(path: "../../External/SDLKit")
    ],
    targets: [
        .executableTarget(
            name: "SDLComposerExperiment",
            dependencies: [
                .product(name: "SDLKit", package: "SDLKit")
            ],
            path: "Sources/SDLComposerExperiment"
        )
    ]
)

