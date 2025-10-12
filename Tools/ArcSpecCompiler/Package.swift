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
    targets: [
        .executableTarget(
            name: "ArcSpecCompiler",
            path: "Sources"
        ),
        .testTarget(
            name: "ArcSpecCompilerTests",
            path: "Tests"
        )
    ]
)
