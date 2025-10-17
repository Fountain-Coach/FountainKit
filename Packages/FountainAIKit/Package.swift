// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainAIKit",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "FountainAIKit", targets: ["FountainAIKit"])
    ],
    dependencies: [
        .package(path: "../FountainCore")
    ],
    targets: [
        .target(
            name: "FountainAIKit",
            dependencies: [
                .product(name: "FountainAICore", package: "FountainCore")
            ]
        )
    ]
)

