// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "fountain-editor-mini-tests",
    platforms: [ .macOS(.v14) ],
    products: [
        .library(name: "FountainEditorMiniCore", targets: ["FountainEditorMiniCore"]) 
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FountainEditorMiniCore",
            dependencies: []
        ),
        .testTarget(
            name: "FountainEditorMiniTests",
            dependencies: ["FountainEditorMiniCore"]
        )
    ]
)
