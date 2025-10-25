// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TeatroAudioBridge",
    platforms: [ .macOS(.v14) ],
    products: [
        .library(name: "TeatroAudio", targets: ["TeatroAudio"]) // Expose module name TeatroAudio
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TeatroAudio",
            dependencies: [],
            path: "Sources/TeatroAudio"
        )
    ]
)

