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
        .executable(name: "openapi-jsonify", targets: ["openapi-jsonify"]),
        .executable(name: "clientgen-service", targets: ["clientgen-service"]),
        .executable(name: "sse-client", targets: ["sse-client"]),
        .executable(name: "openapi-to-facts", targets: ["openapi-to-facts"]),
        .executable(name: "instrument-lint", targets: ["instrument-lint"]),
        .executable(name: "instrument-new", targets: ["instrument-new"]),
        .executable(name: "instrument-new-service-server", targets: ["instrument-new-service-server"]),
        .plugin(name: "EnsureOpenAPIConfigPlugin", targets: ["EnsureOpenAPIConfigPlugin"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "OpenAPICurator",
            dependencies: []
        ),
        .target(
            name: "InstrumentNewCore",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "openapi-to-facts",
            dependencies: [
                "Yams",
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "instrument-lint",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "instrument-new",
            dependencies: [
                "InstrumentNewCore"
            ]
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
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "openapi-jsonify",
            dependencies: [
                "Yams"
            ]
        ),
        .executableTarget(
            name: "clientgen-service",
            dependencies: []
        ),
        .executableTarget(
            name: "sse-client",
            dependencies: []
        ),
        .testTarget(
            name: "InstrumentNewTests",
            dependencies: [
                "InstrumentNewCore"
            ]
        ),
        .testTarget(
            name: "OpenAPICuratorTests",
            dependencies: [
                "OpenAPICurator"
            ]
        ),
        .testTarget(
            name: "OpenAPIToFactsTests",
            dependencies: [
                "openapi-to-facts"
            ]
        ),
        .testTarget(
            name: "InstrumentLintTests",
            dependencies: [
                "instrument-lint"
            ]
        ),
        .testTarget(
            name: "InstrumentNewServiceTests",
            dependencies: [
                "InstrumentNewService",
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "InstrumentNewService",
            dependencies: [
                "InstrumentNewCore",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainRuntime", package: "FountainCore")
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "instrument-new-service-server",
            dependencies: [
                "InstrumentNewService",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ]
        ),
        .plugin(
            name: "EnsureOpenAPIConfigPlugin",
            capability: .buildTool()
        )
    ]
)
