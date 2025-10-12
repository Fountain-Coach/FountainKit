// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ArcSpecCompiler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "arcspec-compiler", targets: ["ArcSpecCompiler"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.1")
    ],
    targets: [
        .executableTarget(
            name: "ArcSpecCompiler",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "ArcSpecCompilerTests",
            dependencies: [
                "ArcSpecCompiler"
            ],
            path: "Tests"
        )
    ]
)
