// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainProviders",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "ProviderOpenAI", targets: ["ProviderOpenAI"]),
        .library(name: "ProviderLocalLLM", targets: ["ProviderLocalLLM"]),
        .library(name: "ProviderGateway", targets: ["ProviderGateway"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainGatewayKit")
    ],
    targets: [
        .target(
            name: "ProviderOpenAI",
            dependencies: [
                .product(name: "FountainAICore", package: "FountainCore")
            ]
        ),
        .target(
            name: "ProviderLocalLLM",
            dependencies: [
                "ProviderOpenAI",
                .product(name: "FountainAICore", package: "FountainCore")
            ]
        ),
        .target(
            name: "ProviderGateway",
            dependencies: [
                .product(name: "FountainAICore", package: "FountainCore"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit")
            ]
        )
    ]
)

