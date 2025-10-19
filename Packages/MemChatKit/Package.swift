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
        .package(path: "../FountainProviders")
    ],
    targets: [
        .target(
            name: "MemChatKit",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "ProviderOpenAI", package: "FountainProviders"),
                .product(name: "ProviderGateway", package: "FountainProviders")
            ]
        ),
        .testTarget(
            name: "MemChatKitTests",
            dependencies: ["MemChatKit", .product(name: "FountainStoreClient", package: "FountainCore")]
        )
    ]
)
