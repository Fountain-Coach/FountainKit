// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainExamples",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FountainExamples", targets: ["FountainExamples"]),
        .executable(name: "hello-fountainai-teatro", targets: ["HelloFountainAITeatro"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainGatewayKit"),
        .package(path: "../FountainServiceKit-Planner"),
        .package(path: "../FountainServiceKit-FunctionCaller")
    ],
    targets: [
        .target(
            name: "FountainExamples",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "GatewayPersonaOrchestrator", package: "FountainGatewayKit"),
                .product(name: "PlannerService", package: "FountainServiceKit-Planner"),
                .product(name: "FunctionCallerService", package: "FountainServiceKit-FunctionCaller")
            ]
        ),
        .executableTarget(
            name: "HelloFountainAITeatro",
            dependencies: [
                "FountainExamples"
            ]
        ),
        .testTarget(
            name: "FountainExamplesTests",
            dependencies: [
                "FountainExamples"
            ]
        )
    ]
)
