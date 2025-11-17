// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BlankApp",
    platforms: [ .macOS(.v14) ],
    products: [
        .executable(name: "blank-page-app", targets: ["blank-page-app"])
    ],
    targets: [
        .executableTarget(
            name: "blank-page-app",
            path: "Sources/blank-page-app",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BlankAppUITests",
            dependencies: ["blank-page-app"],
            path: "Tests/BlankAppUITests",
            resources: [.process("Baselines")]
        )
    ]
)
