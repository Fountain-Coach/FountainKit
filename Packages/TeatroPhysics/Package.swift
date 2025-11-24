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
        ),
        .library(
            name: "TeatroPhysicsBullet",
            targets: ["TeatroPhysicsBullet"]
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
        .target(
            name: "BulletShim",
            path: "Sources/BulletShim",
            publicHeadersPath: "include",
            cxxSettings: [
                // Homebrew and /usr/local search paths for Bullet headers
                .unsafeFlags(["-I/opt/homebrew/include", "-I/opt/homebrew/include/bullet",
                              "-I/usr/local/include", "-I/usr/local/include/bullet"])
            ],
            linkerSettings: [
                .linkedLibrary("BulletDynamics"),
                .linkedLibrary("BulletCollision"),
                .linkedLibrary("LinearMath"),
                .unsafeFlags(["-L/opt/homebrew/lib", "-L/usr/local/lib"])
            ]
        ),
        .target(
            name: "TeatroPhysicsBullet",
            dependencies: [
                "TeatroPhysics",
                "BulletShim"
            ],
            path: "Sources/TeatroPhysicsBullet"
        ),
        .testTarget(
            name: "TeatroPhysicsTests",
            dependencies: ["TeatroPhysics"],
            path: "Tests/TeatroPhysicsTests"
        )
    ]
)
