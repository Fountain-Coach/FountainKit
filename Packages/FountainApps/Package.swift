// swift-tools-version: 6.1
import PackageDescription
import Foundation

let package = Package(
    name: "FountainApps",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "fountain-editor-service-server", targets: ["fountain-editor-service-server"]),
        .library(name: "FountainEditorCoreKit", targets: ["fountain-editor-service-core"]) 
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "fountain-editor-service-core",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/fountain-editor-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "fountain-editor-service-server",
            dependencies: [
                "fountain-editor-service-core",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/fountain-editor-service-server"
        )
    ]
)

