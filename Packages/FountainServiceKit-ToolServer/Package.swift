// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-ToolServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ToolServer", targets: ["ToolServer"]),
        .library(name: "ToolServerService", targets: ["ToolServerService"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Fountain-Coach/toolsmith.git", exact: "1.0.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "ToolServer",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Toolsmith", package: "toolsmith"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Numerics", package: "swift-numerics"),
                .product(name: "Atomics", package: "swift-atomics")
            ],
            exclude: ["Dockerfile"],
            resources: [
                .process("openapi.yaml")
            ]
        ),
        .target(
            name: "ToolServerService",
            dependencies: [
                "ToolServer"
            ],
            exclude: ["HTTPServer.swift"]
        )
    ]
)
