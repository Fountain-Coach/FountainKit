// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainGatewayKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FountainAIAdapters", targets: ["FountainAIAdapters"]),
        .library(name: "GatewayPersonaOrchestrator", targets: ["GatewayPersonaOrchestrator"]),
        .library(name: "LLMGatewayPlugin", targets: ["LLMGatewayPlugin"]),
        .library(name: "AuthGatewayPlugin", targets: ["AuthGatewayPlugin"]),
        .library(name: "RateLimiterGatewayPlugin", targets: ["RateLimiterGatewayPlugin"]),
        .library(name: "BudgetBreakerGatewayPlugin", targets: ["BudgetBreakerGatewayPlugin"]),
        .library(name: "PayloadInspectionGatewayPlugin", targets: ["PayloadInspectionGatewayPlugin"]),
        .library(name: "DestructiveGuardianGatewayPlugin", targets: ["DestructiveGuardianGatewayPlugin"]),
        .library(name: "RoleHealthCheckGatewayPlugin", targets: ["RoleHealthCheckGatewayPlugin"]),
        .library(name: "SecuritySentinelGatewayPlugin", targets: ["SecuritySentinelGatewayPlugin"]),
        .library(name: "CuratorGatewayPlugin", targets: ["CuratorGatewayPlugin"]),
        .library(name: "ChatKitGatewayPlugin", targets: ["ChatKitGatewayPlugin"]),
        .library(name: "PublishingFrontend", targets: ["PublishingFrontend"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainAPIClients"),
        .package(path: "../FountainTooling"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "FountainAIAdapters",
            dependencies: [
                .product(name: "FountainAICore", package: "FountainCore"),
                .product(name: "LLMGatewayAPI", package: "FountainAPIClients"),
                .product(name: "SemanticBrowserAPI", package: "FountainAPIClients"),
                .product(name: "PersistAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients")
            ]
        ),
        .target(
            name: "LLMGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .target(
            name: "AuthGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .target(
            name: "RateLimiterGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "BudgetBreakerGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "PayloadInspectionGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "DestructiveGuardianGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "RoleHealthCheckGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "SecuritySentinelGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "CuratorGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "OpenAPICurator", package: "FountainTooling")
            ]
        ),
        .target(
            name: "ChatKitGatewayPlugin",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                "LLMGatewayPlugin"
            ]
        ),
        .target(
            name: "GatewayPersonaOrchestrator",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                "SecuritySentinelGatewayPlugin",
                "DestructiveGuardianGatewayPlugin"
            ]
        ),
        .target(
            name: "PublishingFrontend",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                "Yams"
            ]
        ),
        .testTarget(
            name: "PublishingFrontendTests",
            dependencies: [
                "PublishingFrontend",
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .testTarget(
            name: "FountainAIAdaptersTests",
            dependencies: [
                "FountainAIAdapters"
            ],
            path: "Tests/FountainAIAdaptersTests"
        )
    ]
)
