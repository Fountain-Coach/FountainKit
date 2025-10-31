// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-MIDI",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "MIDIService", targets: ["MIDIService"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainTooling"),
        .package(path: "../FountainTelemetryKit"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "MIDIService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
