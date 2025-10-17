// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainDevHarness",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "FountainDevHarness", targets: ["FountainDevHarness"])    
    ],
    dependencies: [
        .package(path: "../FountainAIKit")
    ],
    targets: [
        .target(
            name: "FountainDevHarness",
            dependencies: [
                .product(name: "FountainAIKit", package: "FountainAIKit")
            ]
        )
    ]
)

