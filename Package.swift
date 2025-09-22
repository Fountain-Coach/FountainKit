// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FountainKitWorkspace", targets: ["FountainKitWorkspace"])
    ],
    dependencies: [
        .package(path: "Packages/FountainCore"),
        .package(path: "Packages/FountainAPIClients"),
        .package(path: "Packages/FountainGatewayKit"),
        .package(path: "Packages/FountainServiceKit-Planner"),
        .package(path: "Packages/FountainServiceKit-FunctionCaller"),
        .package(path: "Packages/FountainServiceKit-Bootstrap"),
        .package(path: "Packages/FountainServiceKit-Awareness"),
        .package(path: "Packages/FountainServiceKit-Persist"),
        .package(path: "Packages/FountainServiceKit-SemanticBrowser"),
        .package(path: "Packages/FountainServiceKit-ToolsFactory"),
        .package(path: "Packages/FountainServiceKit-ToolServer"),
        .package(path: "Packages/FountainTelemetryKit"),
        .package(path: "Packages/FountainTooling"),
        .package(path: "Packages/FountainApps"),
        .package(path: "Packages/FountainSpecCuration"),
        .package(path: "Packages/FountainExamples")
    ],
    targets: [
        .target(
            name: "FountainKitWorkspace",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "GatewayPersonaOrchestrator", package: "FountainGatewayKit"),
                .product(name: "PlannerService", package: "FountainServiceKit-Planner"),
                .product(name: "FunctionCallerService", package: "FountainServiceKit-FunctionCaller"),
                .product(name: "BootstrapService", package: "FountainServiceKit-Bootstrap"),
                .product(name: "AwarenessService", package: "FountainServiceKit-Awareness"),
                .product(name: "PersistService", package: "FountainServiceKit-Persist"),
                .product(name: "SemanticBrowserService", package: "FountainServiceKit-SemanticBrowser"),
                .product(name: "ToolsFactoryService", package: "FountainServiceKit-ToolsFactory"),
                .product(name: "ToolServer", package: "FountainServiceKit-ToolServer"),
                .product(name: "MIDI2Core", package: "FountainTelemetryKit"),
                .product(name: "OpenAPICurator", package: "FountainTooling"),
                .product(name: "OpenAPISpecs", package: "FountainSpecCuration"),
                .product(name: "FountainExamples", package: "FountainExamples")
            ],
            path: "Workspace"
        )
    ]
)
