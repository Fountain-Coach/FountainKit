// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TeatroCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TeatroCore", targets: ["TeatroCore"])
    ],
    targets: [
        .target(
            name: "TeatroCore",
            dependencies: []
        )
    ]
)
