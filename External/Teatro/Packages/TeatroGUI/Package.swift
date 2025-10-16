// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TeatroGUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TeatroGUI", targets: ["TeatroGUI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TeatroGUI",
            dependencies: []
        )
    ]
)
