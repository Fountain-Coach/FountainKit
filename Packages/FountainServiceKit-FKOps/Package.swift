// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-FKOps",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FKOpsService", targets: ["FKOpsService"])    
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(path: "../FountainTooling"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "FKOpsService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)

