// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainApps",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "gateway-server", targets: ["gateway-server"]),
        .executable(name: "gateway-ci-smoke", targets: ["gateway-ci-smoke"]),
        .executable(name: "tools-factory-server", targets: ["tools-factory-server"]),
        .executable(name: "tool-server", targets: ["tool-server"]),
        .executable(name: "planner-server", targets: ["planner-server"]),
        .executable(name: "function-caller-server", targets: ["function-caller-server"]),
        .executable(name: "persist-server", targets: ["persist-server"]),
        .executable(name: "baseline-awareness-server", targets: ["baseline-awareness-server"]),
        .executable(name: "bootstrap-server", targets: ["bootstrap-server"]),
        .executable(name: "publishing-frontend", targets: ["publishing-frontend"]),
        .executable(name: "tutor-dashboard", targets: ["tutor-dashboard"]),
        .executable(name: "FountainLauncherUI", targets: ["FountainLauncherUI"]),
        .executable(name: "local-agent-manager", targets: ["local-agent-manager"]),
        .executable(name: "mock-localagent-server", targets: ["mock-localagent-server"])
        ,
        .executable(name: "engraver-studio-app", targets: ["engraver-studio-app"]),
        .executable(name: "engraver-chat-tui", targets: ["engraver-chat-tui"]),
        .executable(name: "llm-doctor", targets: ["llm-doctor"]),
        .executable(name: "engraver-direct", targets: ["engraver-direct"]),
        .library(name: "EngraverChatCore", targets: ["EngraverChatCore"]),
        .library(name: "EngraverStudio", targets: ["EngraverStudio"]),
        .executable(name: "fk", targets: ["fk"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainAIKit"),
        .package(path: "../FountainProviders"),
        .package(path: "../FountainDevHarness"),
        .package(path: "../FountainAPIClients"),
        .package(path: "../FountainGatewayKit"),
        .package(path: "../FountainServiceKit-Planner"),
        .package(path: "../FountainServiceKit-FunctionCaller"),
        .package(path: "../FountainServiceKit-Bootstrap"),
        .package(path: "../FountainServiceKit-Awareness"),
        .package(path: "../FountainServiceKit-Persist"),
        
        .package(path: "../FountainServiceKit-ToolsFactory"),
        .package(path: "../FountainServiceKit-ToolServer"),
        .package(path: "../FountainServiceKit-FKOps"),
        .package(path: "../FountainTooling"),
        .package(path: "../../Tools/PersistenceSeeder"),
        .package(path: "../../External/Teatro/Packages/TeatroGUI"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/Fountain-Coach/swiftcurseskit.git", exact: "0.2.0"),
        .package(url: "https://github.com/Fountain-Coach/swift-secretstore.git", exact: "0.1.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "gateway-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
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
                .product(name: "ChatKitGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "GatewayPersonaOrchestrator", package: "FountainGatewayKit"),
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                "Yams"
            ],
            exclude: ["README.md"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "llm-doctor",
            dependencies: []
        ),
        .executableTarget(
            name: "engraver-direct",
            dependencies: []
        ),
        .executableTarget(
            name: "gateway-ci-smoke",
            dependencies: [
                .product(name: "GatewayAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "fk",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
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
            ],
            exclude: ["README.md"]
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
                .product(name: "SpeechAtlasService", package: "FountainServiceKit-Persist"),
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
            name: "publishing-frontend",
            dependencies: [
                .product(name: "PublishingFrontend", package: "FountainGatewayKit")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "tutor-dashboard",
            dependencies: [
                .product(name: "TutorDashboard", package: "FountainAPIClients"),
                .product(name: "SwiftCursesKit", package: "swiftcurseskit")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "FountainLauncherUI",
            dependencies: [
                .product(name: "SecretStore", package: "swift-secretstore"),
                "EngraverStudio"
            ],
            path: "Sources/FountainLauncherUI",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "engraver-studio-app",
            dependencies: [
                "EngraverStudio"
            ],
            path: "Sources/engraver-studio-app"
        ),
        .executableTarget(
            name: "local-agent-manager",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "mock-localagent-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "EngraverChatCore",
            dependencies: [
                .product(name: "FountainAICore", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "LLMGatewayAPI", package: "FountainAPIClients"),
                .product(name: "AwarenessAPI", package: "FountainAPIClients"),
                .product(name: "BootstrapAPI", package: "FountainAPIClients"),
                .product(name: "SemanticBrowserAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/EngraverChatCore"
        ),
        .target(
            name: "EngraverStudio",
            dependencies: [
                "EngraverChatCore",
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "FountainDevHarness", package: "FountainDevHarness"),
                .product(name: "ProviderOpenAI", package: "FountainProviders"),
                .product(name: "ProviderLocalLLM", package: "FountainProviders"),
                .product(name: "ProviderGateway", package: "FountainProviders"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "TeatroGUI", package: "TeatroGUI")
            ],
            path: "Sources/engraver-studio"
        ),
        .executableTarget(
            name: "engraver-chat-tui",
            dependencies: [
                "EngraverChatCore",
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "FountainDevHarness", package: "FountainDevHarness"),
                .product(name: "ProviderOpenAI", package: "FountainProviders"),
                .product(name: "ProviderLocalLLM", package: "FountainProviders"),
                .product(name: "ProviderGateway", package: "FountainProviders"),
                .product(name: "SwiftCursesKit", package: "swiftcurseskit"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/engraver-chat-tui"
        ),
        .executableTarget(
            name: "fk-ops-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FKOpsService", package: "FountainServiceKit-FKOps"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ]
        ),
        .testTarget(
            name: "FountainLauncherUITests",
            dependencies: ["FountainLauncherUI"]
        ),
        .testTarget(
            name: "EngraverStudioTests",
            dependencies: ["EngraverStudio", "EngraverChatCore", "engraver-chat-tui"],
            path: "Tests/EngraverStudioTests"
        ),
        .testTarget(
            name: "FountainDevScriptsTests",
            dependencies: []
        ),
        .testTarget(
            name: "GatewayServerTests",
            dependencies: [
                "gateway-server",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "ChatKitGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "GatewayAPI", package: "FountainAPIClients")
            ]
        )
    ]
)
