// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainApps-SemanticBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "semantic-browser-server", targets: ["semantic-browser-server"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainServiceKit-SemanticBrowser")
    ],
    targets: [
        .executableTarget(
            name: "semantic-browser-server",
            dependencies: [
                .product(name: "SemanticBrowserService", package: "FountainServiceKit-SemanticBrowser"),
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        )
    ]
)

