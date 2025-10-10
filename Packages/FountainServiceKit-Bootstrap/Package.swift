// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-Bootstrap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "BootstrapService", targets: ["BootstrapService"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainTooling"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "BootstrapService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Numerics", package: "swift-numerics"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
