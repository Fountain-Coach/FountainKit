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
        .package(path: "../FountainCore")
    ],
    targets: [
        .target(
            name: "PersistService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        )
    ]
)
