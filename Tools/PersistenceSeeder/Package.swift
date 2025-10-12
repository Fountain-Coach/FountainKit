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
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.1")
    ],
    targets: [
        .executableTarget(
            name: "PersistenceSeeder",
            dependencies: [
                .product(name: "Yams", package: "Yams")
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
