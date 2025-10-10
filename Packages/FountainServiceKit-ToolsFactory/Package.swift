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
        .package(path: "../FountainServiceKit-ToolServer"),
        .package(path: "../FountainTooling"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "ToolsFactoryService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "ToolServer", package: "FountainServiceKit-ToolServer"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
