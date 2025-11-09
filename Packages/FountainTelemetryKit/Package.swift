// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainTelemetryKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MIDI2Models", targets: ["MIDI2Models"]),
        .library(name: "MIDI2Core", targets: ["MIDI2Core"]),
        .library(name: "MIDI2Transports", targets: ["MIDI2Transports"]),
        .library(name: "SSEOverMIDI", targets: ["SSEOverMIDI"]),
        .library(name: "FlexBridge", targets: ["FlexBridge"]),
        .executable(name: "flexctl", targets: ["flexctl"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(url: "https://github.com/Fountain-Coach/midi2.git", from: "0.3.1")
    ],
    targets: [
        .target(
            name: "MIDI2Models",
            dependencies: [
                .product(name: "ResourceLoader", package: "FountainCore")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "MIDI2Core",
            dependencies: [
                .product(name: "MIDI2", package: "midi2")
            ]
        ),
        .target(
            name: "MIDI2Transports",
            dependencies: []
        ),
        .testTarget(
            name: "MIDI2TransportsTests",
            dependencies: ["MIDI2Transports"],
            path: "Tests/MIDI2TransportsTests"
        ),
        .target(
            name: "SSEOverMIDI",
            dependencies: [
                "MIDI2Core",
                "MIDI2Transports",
                .product(name: "MIDI2", package: "midi2")
            ]
        ),
        .target(
            name: "FlexBridge",
            dependencies: [
                "MIDI2Core",
                "MIDI2Transports"
            ]
        ),
        .executableTarget(
            name: "flexctl",
            dependencies: [
                "MIDI2Core",
                .product(name: "MIDI2", package: "midi2")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
