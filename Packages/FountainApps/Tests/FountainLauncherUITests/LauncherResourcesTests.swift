import XCTest
@testable import FountainLauncherUI

final class LauncherResourcesTests: XCTestCase {
    func testLocatesSpecsInCurationPackage() throws {
        let repoRoot = Self.repositoryRoot()
        let spec = LauncherResources.locateSpecDirectory(repoRoot: repoRoot.path)
        XCTAssertNotNil(spec)
        XCTAssertTrue(spec?.path.contains("Packages/FountainSpecCuration/openapi") ?? false,
                      "Expected spec directory to live under Packages/FountainSpecCuration/openapi, got \(spec?.path ?? "nil")")
    }

    func testLocatesScriptsDirectory() throws {
        let repoRoot = Self.repositoryRoot()
        let scripts = LauncherResources.locateScriptsDirectory(repoRoot: repoRoot.path)
        XCTAssertNotNil(scripts)
        XCTAssertTrue(scripts?.path.hasSuffix("/Scripts") ?? false)
        let launcher = LauncherResources.launcherScriptURL(repoRoot: repoRoot.path)
        XCTAssertNotNil(launcher)
    }

    func testEnvironmentOverridesTakePrecedence() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let customSpecs = temp.appendingPathComponent("curated")
        try fm.createDirectory(at: customSpecs, withIntermediateDirectories: true)
        let customScripts = temp.appendingPathComponent("helpers")
        try fm.createDirectory(at: customScripts, withIntermediateDirectories: true)
        let launcher = customScripts.appendingPathComponent("launcher")
        _ = fm.createFile(atPath: launcher.path, contents: Data(), attributes: nil)

        let env: [String: String] = [
            LauncherResources.specsOverrideKey: "curated",
            LauncherResources.scriptsOverrideKey: "helpers"
        ]

        let spec = LauncherResources.locateSpecDirectory(repoRoot: temp.path, environment: env)
        XCTAssertEqual(spec?.standardizedFileURL.path, customSpecs.standardizedFileURL.path)
        let script = LauncherResources.launcherScriptURL(repoRoot: temp.path, environment: env)
        XCTAssertEqual(script?.standardizedFileURL.path, launcher.standardizedFileURL.path)
    }

    private static func repositoryRoot(file: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: String(describing: file))
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
