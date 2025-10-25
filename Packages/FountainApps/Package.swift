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
        .executable(name: "mock-localagent-server", targets: ["mock-localagent-server"]),
        .executable(name: "audiotalk-server", targets: ["audiotalk-server"])
        ,
        .executable(name: "engraver-studio-app", targets: ["engraver-studio-app"]),
        .executable(name: "gateway-console", targets: ["gateway-console"]),
        .executable(name: "gateway-console-app", targets: ["gateway-console-app"]),
        .executable(name: "engraver-chat-tui", targets: ["engraver-chat-tui"]),
        .executable(name: "audiotalk-cli", targets: ["audiotalk-cli"]),
        .executable(name: "audiotalk-ci-smoke", targets: ["audiotalk-ci-smoke"]),
        .executable(name: "m2-smoke", targets: ["m2-smoke"]),
        .executable(name: "engraving-app", targets: ["engraving-app"]),
        .executable(name: "memchat-app", targets: ["memchat-app"]),
        .executable(name: "memchat-teatro", targets: ["memchat-teatro"]),
        .executable(name: "engraving-demo-seed", targets: ["engraving-demo-seed"]),
        .executable(name: "memchat-concept-seed", targets: ["memchat-concept-seed"]),
        .executable(name: "memchat-save-reply", targets: ["memchat-save-reply"]),
        .executable(name: "memchat-save-continuity", targets: ["memchat-save-continuity"]),
        .executable(name: "memchat-save-plan", targets: ["memchat-save-plan"]),
        .executable(name: "llm-doctor", targets: ["llm-doctor"]),
        .executable(name: "engraver-direct", targets: ["engraver-direct"]),
        .library(name: "EngraverChatCore", targets: ["EngraverChatCore"]),
        .library(name: "EngraverStudio", targets: ["EngraverStudio"]),
        .library(name: "MetalViewKit", targets: ["MetalViewKit"]),
        .library(name: "MetalComputeKit", targets: ["MetalComputeKit"]),
        .library(name: "CoreMLKit", targets: ["CoreMLKit"]),
        .executable(name: "metalcompute-demo", targets: ["metalcompute-demo"]),
        .executable(name: "metalcompute-tests", targets: ["metalcompute-tests"]),
        .executable(name: "coreml-demo", targets: ["coreml-demo"]),
        .executable(name: "coreml-fetch", targets: ["coreml-fetch"]),
        .executable(name: "ml-audio2midi", targets: ["ml-audio2midi"]),
        .executable(name: "ml-basicpitch2midi", targets: ["ml-basicpitch2midi"]),
        .executable(name: "ml-yamnet2midi", targets: ["ml-yamnet2midi"]),
        .executable(name: "ml-sampler-smoke", targets: ["ml-sampler-smoke"]),
        .executable(name: "metalview-demo-app", targets: ["metalview-demo-app"]),
        .executable(name: "fk", targets: ["fk"])
        ,
        .executable(name: "composer-studio", targets: ["composer-studio"]),
        .executable(name: "qc-mock-app", targets: ["qc-mock-app"]),
        .executable(name: "qcmockcore-tests", targets: ["qcmockcore-tests"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainAIKit"),
        .package(path: "../FountainProviders"),
        .package(path: "../MemChatKit"),
        .package(path: "../FountainDevHarness"),
        .package(path: "../FountainAPIClients"),
        .package(path: "../FountainGatewayKit"),
        .package(path: "../FountainServiceKit-Planner"),
        .package(path: "../FountainServiceKit-FunctionCaller"),
        .package(path: "../FountainServiceKit-Bootstrap"),
        .package(path: "../FountainServiceKit-Awareness"),
        .package(path: "../FountainServiceKit-Persist"),
        .package(path: "../FountainServiceKit-AudioTalk"),
        
        .package(path: "../FountainServiceKit-ToolsFactory"),
        .package(path: "../FountainServiceKit-ToolServer"),
        .package(path: "../FountainServiceKit-FKOps"),
        .package(path: "../FountainTooling"),
        .package(path: "../FountainTelemetryKit"),
        .package(path: "../../Tools/PersistenceSeeder"),
        .package(path: "../../External/TeatroFull"),
        
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/Fountain-Coach/swiftcurseskit.git", exact: "0.2.0"),
        .package(url: "https://github.com/Fountain-Coach/swift-secretstore.git", exact: "0.1.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.0.0"),
        // MIDI 2.0 + MIDI-CI helpers (Discovery, Property Exchange)
        .package(url: "https://github.com/Fountain-Coach/midi2.git", branch: "main"),
        // MIDI2 Instrument Bridge (sampler) — pin to released tag
        .package(url: "https://github.com/Fountain-Coach/midi2sampler.git", exact: "0.1.1")
    ],
    targets: [
        .target(
            name: "QCMockCore",
            dependencies: [],
            path: "Sources/QCMockCore"
        ),
        .target(
            name: "QCMockServiceCore",
            dependencies: ["QCMockCore"],
            path: "Sources/QCMockServiceCore"
        ),
        .executableTarget(
            name: "gateway-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "PublishingFrontend", package: "FountainGatewayKit"),
                .product(name: "LLMGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "PolicyGatewayPlugin", package: "FountainGatewayKit"),
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
            name: "ml-sampler-smoke",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ml-sampler-smoke"
        ),
        .executableTarget(
            name: "ml-audio2midi",
            dependencies: [
                "CoreMLKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Midi2SamplerDSP", package: "midi2sampler")
            ],
            path: "Sources/ml-audio2midi"
        ),
        .executableTarget(
            name: "ml-basicpitch2midi",
            dependencies: [
                "CoreMLKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Midi2SamplerDSP", package: "midi2sampler")
            ],
            path: "Sources/ml-basicpitch2midi"
        ),
        .executableTarget(
            name: "ml-yamnet2midi",
            dependencies: [
                "CoreMLKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ml-yamnet2midi"
        ),
        .executableTarget(
            name: "metalcompute-demo",
            dependencies: ["MetalComputeKit"],
            path: "Sources/metalcompute-demo"
        ),
        .executableTarget(
            name: "metalcompute-tests",
            dependencies: ["MetalComputeKit"],
            path: "Sources/metalcompute-tests"
        ),
        .executableTarget(
            name: "coreml-demo",
            dependencies: ["CoreMLKit"],
            path: "Sources/coreml-demo"
        ),
        .executableTarget(
            name: "coreml-fetch",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/coreml-fetch"
        ),
        .target(
            name: "MetalViewKit",
            dependencies: [
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Sources/MetalViewKit",
            exclude: ["AGENTS.md"]
        ),
        .target(
            name: "MetalComputeKit",
            dependencies: [],
            path: "Sources/MetalComputeKit",
            exclude: ["AGENTS.md"]
        ),
        .target(
            name: "CoreMLKit",
            dependencies: [],
            path: "Sources/CoreMLKit",
            exclude: ["AGENTS.md"]
        ),
        .executableTarget(
            name: "composer-studio",
            dependencies: [],
            path: "Sources/composer-studio",
            exclude: ["AGENTS.md"]
        ),
        .executableTarget(
            name: "qc-mock-app",
            dependencies: [
                "QCMockCore",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/qc-mock-app",
            exclude: ["AGENTS.md"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "qc-mock-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                "QCMockServiceCore"
            ],
            path: "Sources/qc-mock-service",
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "qc-mock-service-server",
            dependencies: [
                "qc-mock-service",
                .product(name: "FountainRuntime", package: "FountainCore")
            ],
            path: "Sources/qc-mock-service-server"
        ),
        .executableTarget(
            name: "qcmockcore-tests",
            dependencies: ["QCMockCore"],
            path: "Sources/qcmockcore-tests"
        ),
        .testTarget(
            name: "QCMockCoreTests",
            dependencies: ["QCMockCore"],
            path: "Tests/QCMockCoreTests"
        ),
        .testTarget(
            name: "QCMockServiceSpecTests",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Tests/QCMockServiceSpecTests"
        ),
        .testTarget(
            name: "QCMockHandlersTests",
            dependencies: [
                "qc-mock-service",
                "QCMockServiceCore"
            ],
            path: "Tests/QCMockHandlersTests"
        ),
        .executableTarget(
            name: "qcmockservice-tests",
            dependencies: ["QCMockServiceCore"],
            path: "Sources/qcmockservice-tests"
        ),
        .executableTarget(
            name: "qc-mock-handlers-tests",
            dependencies: ["qc-mock-service"],
            path: "Sources/qc-mock-handlers-tests"
        ),
        .executableTarget(
            name: "m2-smoke",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FunctionCallerService", package: "FountainServiceKit-FunctionCaller"),
                .product(name: "PlannerService", package: "FountainServiceKit-Planner")
            ]
        ),
        .executableTarget(
            name: "audiotalk-ci-smoke",
            dependencies: [
                .product(name: "AudioTalkAPI", package: "FountainAPIClients"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ]
        ),
        .executableTarget(
            name: "audiotalk-cli",
            dependencies: [
                .product(name: "AudioTalkAPI", package: "FountainAPIClients"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "memchat-save-continuity",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-save-continuity"
        ),
        .executableTarget(
            name: "memchat-save-plan",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-save-plan"
        ),
        .executableTarget(
            name: "memchat-save-reply",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-save-reply"
        ),
        .executableTarget(
            name: "memchat-concept-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-concept-seed"
        ),
        .executableTarget(
            name: "engraving-demo-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/engraving-demo-seed"
        ),
        .executableTarget(
            name: "llm-doctor",
            dependencies: [],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "engraver-direct",
            dependencies: [],
            exclude: ["README.md"]
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
            name: "audiotalk-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "AudioTalkService", package: "FountainServiceKit-AudioTalk"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md", "Static"]
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
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/FountainLauncherUI",
            exclude: ["README.md", "AGENTS.md"]
        ),
        .executableTarget(
            name: "engraver-studio-app",
            dependencies: [
                "EngraverStudio",
                "EngraverChatCore",
                .product(name: "FountainDevHarness", package: "FountainDevHarness")
            ],
            path: "Sources/engraver-studio-app"
        ),
        .executableTarget(
            name: "gateway-console",
            dependencies: [
                .product(name: "FountainDevHarness", package: "FountainDevHarness"),
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients")
            ],
            path: "Sources/gateway-console"
        ),
        .executableTarget(
            name: "gateway-console-app",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/gateway-console-app"
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
                .product(name: "ProviderOpenAI", package: "FountainProviders"),
                .product(name: "ProviderLocalLLM", package: "FountainProviders"),
                .product(name: "ProviderGateway", package: "FountainProviders"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "Teatro", package: "TeatroFull")
            ],
            path: "Sources/engraver-studio",
            exclude: ["README.md"]
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
            name: "engraving-tui",
            dependencies: [
                .product(name: "SwiftCursesKit", package: "swiftcurseskit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/engraving-tui"
        ),
        .executableTarget(
            name: "engraving-app",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "ProviderOpenAI", package: "FountainProviders")
            ],
            path: "Sources/engraving-app"
        ),
        .executableTarget(
            name: "memchat-app",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "MemChatKit", package: "MemChatKit"),
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/memchat-app"
        ),
        .executableTarget(
            name: "memchat-teatro",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "MemChatKit", package: "MemChatKit"),
                .product(name: "SecretStore", package: "swift-secretstore"),
                .product(name: "Teatro", package: "TeatroFull")
            ],
            path: "Sources/memchat-teatro"
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
        ,
        .testTarget(
            name: "MetalComputeKitTests",
            dependencies: ["MetalComputeKit"],
            path: "Tests/MetalComputeKitTests"
        ),
        .executableTarget(
            name: "metalview-demo-app",
            dependencies: [
                "MetalViewKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "Teatro", package: "TeatroFull"),
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Sources/metalview-demo-app",
            exclude: ["AGENTS.md"]
        )
    ]
)
