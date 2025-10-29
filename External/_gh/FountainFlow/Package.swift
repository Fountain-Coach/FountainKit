// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainFlow",
    platforms: [ .macOS(.v14) ],
    products: [
        .library(name: "FountainFlow", targets: ["FountainFlow"])
    ],
    dependencies: [
        // Intentional: we depend on AudioKit Flow for early interop
        .package(url: "https://github.com/AudioKit/Flow.git", from: "1.0.4")
    ],
    targets: [
        .target(
            name: "FountainFlow",
            dependencies: [ .product(name: "Flow", package: "Flow") ],
            path: "Sources/FountainFlow"
        ),
        .testTarget(
            name: "FountainFlowTests",
            dependencies: ["FountainFlow"],
            path: "Tests/FountainFlowTests"
        )
    ]
)
