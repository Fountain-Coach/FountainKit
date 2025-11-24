// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TeatroPhysics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TeatroPhysics",
            targets: ["TeatroPhysics"]
        )
    ],
    dependencies: [
        // Intentionally empty for now; keep the core engine headless and renderer‑agnostic.
    ],
    targets: [
        .target(
            name: "TeatroPhysics",
            dependencies: [],
            path: "Sources/TeatroPhysics"
        ),
        .testTarget(
            name: "TeatroPhysicsTests",
            dependencies: ["TeatroPhysics"],
            path: "Tests/TeatroPhysicsTests"
        )
    ]
)

