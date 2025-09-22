// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-SemanticBrowser",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SemanticBrowserService", targets: ["SemanticBrowserService"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.59.0"),
        .package(url: "https://github.com/typesense/typesense-swift.git", from: "1.0.1"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SemanticBrowserService",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "Typesense", package: "typesense-swift"),
                .product(name: "Numerics", package: "swift-numerics")
            ]
        ),
        .testTarget(
            name: "SemanticBrowserServiceTests",
            dependencies: [
                "SemanticBrowserService"
            ]
        )
    ]
)
