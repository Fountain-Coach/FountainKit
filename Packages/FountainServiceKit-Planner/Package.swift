// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainServiceKit-Planner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PlannerService", targets: ["PlannerService"])
    ],
    dependencies: [
        .package(path: "../FountainCore")
    ],
    targets: [
        .target(
            name: "PlannerService",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        )
    ]
)
