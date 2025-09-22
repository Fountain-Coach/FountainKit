// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainExamples",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FountainExamples", targets: ["FountainExamples"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FountainExamples",
            resources: [
                .copy("Examples")
            ]
        )
    ]
)
