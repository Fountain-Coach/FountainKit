// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainAPIClients",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ApiClientsCore", targets: ["ApiClientsCore"]),
        .library(name: "GatewayAPI", targets: ["GatewayAPI"]),
        .library(name: "PersistAPI", targets: ["PersistAPI"]),
        .library(name: "SemanticBrowserAPI", targets: ["SemanticBrowserAPI"]),
        .library(name: "LLMGatewayAPI", targets: ["LLMGatewayAPI"]),
        .library(name: "TutorDashboard", targets: ["TutorDashboard"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        // OpenAPI generator + runtime for generated clients
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "ApiClientsCore",
            dependencies: []
        ),
        .target(
            name: "GatewayAPI",
            dependencies: ["ApiClientsCore"]
        ),
        .target(
            name: "PersistAPI",
            dependencies: ["ApiClientsCore"]
        ),
        .target(
            name: "SemanticBrowserAPI",
            dependencies: [
                "ApiClientsCore",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            plugins: [
                .plugin(name: "OpenAPIGeneratorPlugin", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "LLMGatewayAPI",
            dependencies: ["ApiClientsCore"]
        ),
        .target(
            name: "TutorDashboard",
            dependencies: [
                "ApiClientsCore",
                "Yams"
            ]
        )
    ]
)
