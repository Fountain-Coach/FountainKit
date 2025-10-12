// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PersistenceSeeder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "persistence-seeder", targets: ["PersistenceSeeder"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.1"),
        .package(path: "../../Packages/FountainAPIClients"),
        .package(url: "https://github.com/Fountain-Coach/swift-secretstore.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "PersistenceSeeder",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "PersistenceSeederTests",
            dependencies: ["PersistenceSeeder"],
            path: "Tests"
        )
    ]
)
