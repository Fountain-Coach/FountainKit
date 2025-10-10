// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-ToolServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ToolServer", targets: ["ToolServer"]),
        .library(name: "ToolServerService", targets: ["ToolServerService"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainTooling"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "ToolServer",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            exclude: ["Dockerfile"],
            resources: [
                .process("openapi.yaml")
            ]
        ),
        .target(
            name: "ToolServerService",
            dependencies: [
                "ToolServer",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            exclude: ["HTTPServer.swift"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
