// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainAIKit",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "FountainAIKit", targets: ["FountainAIKit"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainAPIClients"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "FountainAIKit",
            dependencies: [
                .product(name: "FountainAICore", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "AwarenessAPI", package: "FountainAPIClients"),
                .product(name: "BootstrapAPI", package: "FountainAPIClients"),
                .product(name: "SemanticBrowserAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ]
        )
    ]
)
