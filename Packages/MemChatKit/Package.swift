// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MemChatKit",
    platforms: [ .macOS(.v14) ],
    products: [
        .library(name: "MemChatKit", targets: ["MemChatKit"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainAIKit"),
        .package(path: "../FountainProviders"),
        .package(path: "../FountainAPIClients"),
        .package(path: "../../External/Teatro/Packages/TeatroGUI")
    ],
    targets: [
        .target(
            name: "MemChatKit",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "ProviderOpenAI", package: "FountainProviders"),
                .product(name: "ProviderGateway", package: "FountainProviders"),
                .product(name: "SemanticBrowserAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "TeatroGUI", package: "TeatroGUI")
            ]
        ),
        .testTarget(
            name: "MemChatKitTests",
            dependencies: ["MemChatKit", .product(name: "FountainStoreClient", package: "FountainCore")]
        )
    ]
)
