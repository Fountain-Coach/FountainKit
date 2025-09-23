// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-ToolsFactory",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ToolsFactoryService", targets: ["ToolsFactoryService"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainServiceKit-ToolServer")
    ],
    targets: [
        .target(
            name: "ToolsFactoryService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "ToolServer", package: "FountainServiceKit-ToolServer")
            ]
        )
    ]
)
