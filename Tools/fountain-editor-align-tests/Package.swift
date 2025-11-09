// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "fountain-editor-align-tests",
    platforms: [ .macOS(.v14) ],
    products: [],
    dependencies: [
        .package(path: "../../Packages/FountainApps"),
        .package(path: "../fountain-editor-mini-tests"),
        .package(path: "../../External/TeatroFull")
    ],
    targets: [
        .testTarget(
            name: "FountainEditorAlignmentTests",
            dependencies: [
                .product(name: "FountainEditorCoreKit", package: "FountainApps"),
                .product(name: "FountainEditorMiniCore", package: "fountain-editor-mini-tests"),
                .product(name: "Teatro", package: "TeatroFull")
            ],
            resources: [ .copy("Fixtures") ]
        )
    ]
)

