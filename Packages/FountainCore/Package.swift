// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FountainRuntime", targets: ["FountainRuntime"]),
        .library(name: "FountainStoreClient", targets: ["FountainStoreClient"]),
        .library(name: "FountainAICore", targets: ["FountainAICore"]),
        .library(name: "FountainCodex", targets: ["FountainCodex"]),
        .library(name: "ResourceLoader", targets: ["ResourceLoader"]),
        .library(name: "LauncherSignature", targets: ["LauncherSignature"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
        .package(url: "https://github.com/Fountain-Coach/Fountain-Store.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "FountainRuntime",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                "Yams",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Atomics", package: "swift-atomics"),
                "FountainStoreClient",
                .product(name: "FountainStore", package: "Fountain-Store")
            ],
            exclude: ["DNS/README.md"]
        ),
        .target(
            name: "FountainStoreClient",
            dependencies: [
                .product(name: "FountainStore", package: "Fountain-Store")
            ]
        ),
        .target(
            name: "FountainAICore",
            dependencies: []
        ),
        .target(
            name: "FountainCodex",
            dependencies: ["FountainRuntime"],
            exclude: ["FountainCodex", "README.md"],
            sources: ["Reexport.swift"]
        ),
        .target(
            name: "ResourceLoader",
            dependencies: []
        ),
        .target(
            name: "LauncherSignature",
            dependencies: []
        )
    ]
)
