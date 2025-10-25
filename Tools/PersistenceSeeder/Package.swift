// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PersistenceSeeder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PersistenceSeederKit", targets: ["PersistenceSeederKit"]),
        .executable(name: "persistence-seeder", targets: ["PersistenceSeeder"]),
        .executable(name: "persistence-exporter", targets: ["PersistenceExporter"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.1"),
        .package(path: "../../Packages/FountainAPIClients"),
        .package(url: "https://github.com/Fountain-Coach/swift-secretstore.git", from: "0.1.0"),
        .package(path: "../../External/TeatroFull")
    ],
    targets: [
        .target(
            name: "PersistenceSeederKit",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "SecretStore", package: "swift-secretstore"),
                .product(name: "Teatro", package: "TeatroFull")
            ],
            path: "Sources/PersistenceSeederKit"
        ),
        .executableTarget(
            name: "PersistenceSeeder",
            dependencies: [
                "PersistenceSeederKit"
            ],
            path: "Sources/PersistenceSeeder"
        ),
        .executableTarget(
            name: "PersistenceExporter",
            dependencies: [
                "PersistenceSeederKit"
            ],
            path: "Sources/PersistenceExporter"
        ),
        .testTarget(
            name: "PersistenceSeederTests",
            dependencies: ["PersistenceSeederKit"],
            path: "Tests"
        )
    ]
)
