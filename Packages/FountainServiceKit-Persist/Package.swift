// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-Persist",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PersistService", targets: ["PersistService"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainTooling"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "PersistService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .testTarget(
            name: "PersistServiceTests",
            dependencies: [
                "PersistService",
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Tests/PersistServiceTests"
        )
    ]
)
