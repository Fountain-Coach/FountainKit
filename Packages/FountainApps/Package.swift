// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainApps",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "gateway-server", targets: ["gateway-server"]),
        .executable(name: "tools-factory-server", targets: ["tools-factory-server"]),
        .executable(name: "tool-server", targets: ["tool-server"]),
        .executable(name: "planner-server", targets: ["planner-server"]),
        .executable(name: "function-caller-server", targets: ["function-caller-server"]),
        .executable(name: "persist-server", targets: ["persist-server"]),
        .executable(name: "baseline-awareness-server", targets: ["baseline-awareness-server"]),
        .executable(name: "bootstrap-server", targets: ["bootstrap-server"]),
        .executable(name: "semantic-browser-server", targets: ["semantic-browser-server"]),
        .executable(name: "publishing-frontend", targets: ["publishing-frontend"]),
        .executable(name: "tutor-dashboard", targets: ["tutor-dashboard"]),
        .executable(name: "FountainLauncherUI", targets: ["FountainLauncherUI"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainAPIClients"),
        .package(path: "../FountainGatewayKit"),
        .package(path: "../FountainServiceKit-Planner"),
        .package(path: "../FountainServiceKit-FunctionCaller"),
        .package(path: "../FountainServiceKit-Bootstrap"),
        .package(path: "../FountainServiceKit-Awareness"),
        .package(path: "../FountainServiceKit-Persist"),
        .package(path: "../FountainServiceKit-SemanticBrowser"),
        .package(path: "../FountainServiceKit-ToolsFactory"),
        .package(path: "../FountainServiceKit-ToolServer"),
        .package(path: "../FountainTooling"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/Fountain-Coach/swiftcurseskit.git", exact: "0.2.0"),
        .package(url: "https://github.com/Fountain-Coach/swift-secretstore.git", exact: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "gateway-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "PublishingFrontend", package: "FountainGatewayKit"),
                .product(name: "LLMGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "AuthGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "CuratorGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "RateLimiterGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "BudgetBreakerGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "PayloadInspectionGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "DestructiveGuardianGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "RoleHealthCheckGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "SecuritySentinelGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "GatewayPersonaOrchestrator", package: "FountainGatewayKit"),
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                "Yams"
            ]
        ),
        .executableTarget(
            name: "tools-factory-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "ToolsFactoryService", package: "FountainServiceKit-ToolsFactory"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md", "AGENTS.md"]
        ),
        .executableTarget(
            name: "tool-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "ToolServerService", package: "FountainServiceKit-ToolServer"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "planner-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "PlannerService", package: "FountainServiceKit-Planner"),
                "Yams",
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "function-caller-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FunctionCallerService", package: "FountainServiceKit-FunctionCaller"),
                "Yams",
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "persist-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "PersistService", package: "FountainServiceKit-Persist"),
                "Yams",
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "baseline-awareness-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "AwarenessService", package: "FountainServiceKit-Awareness"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "bootstrap-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "BootstrapService", package: "FountainServiceKit-Bootstrap"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "semantic-browser-server",
            dependencies: [
                .product(name: "SemanticBrowserService", package: "FountainServiceKit-SemanticBrowser"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "publishing-frontend",
            dependencies: [
                .product(name: "PublishingFrontend", package: "FountainGatewayKit")
            ]
        ),
        .executableTarget(
            name: "tutor-dashboard",
            dependencies: [
                .product(name: "TutorDashboard", package: "FountainAPIClients"),
                .product(name: "SwiftCursesKit", package: "swiftcurseskit")
            ]
        ),
        .executableTarget(
            name: "FountainLauncherUI",
            dependencies: [
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/FountainLauncherUI"
        ),
        .testTarget(
            name: "FountainLauncherUITests",
            dependencies: ["FountainLauncherUI"]
        )
    ]
)
