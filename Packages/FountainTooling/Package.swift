// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainTooling",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OpenAPICurator", targets: ["OpenAPICurator"]),
        .executable(name: "openapi-curator-cli", targets: ["openapi-curator-cli"]),
        .executable(name: "openapi-curator-service", targets: ["openapi-curator-service"]),
        .executable(name: "clientgen-service", targets: ["clientgen-service"]),
        .executable(name: "sse-client", targets: ["sse-client"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "OpenAPICurator",
            dependencies: []
        ),
        .executableTarget(
            name: "openapi-curator-cli",
            dependencies: [
                "OpenAPICurator",
                "Yams"
            ]
        ),
        .executableTarget(
            name: "openapi-curator-service",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                "OpenAPICurator",
                "Yams",
                .product(name: "LauncherSignature", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "clientgen-service",
            dependencies: []
        ),
        .executableTarget(
            name: "sse-client",
            dependencies: []
        )
    ]
)
