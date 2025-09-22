// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainSpecCuration",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OpenAPISpecs", targets: ["OpenAPISpecs"])
    ],
    targets: [
        .target(
            name: "OpenAPISpecs"
        )
    ]
)
