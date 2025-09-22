// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-FunctionCaller",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FunctionCallerService", targets: ["FunctionCallerService"])
    ],
    dependencies: [
        .package(path: "../FountainCore"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0")
    ],
    targets: [
        .target(
            name: "FunctionCallerService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ]
        )
    ]
)
