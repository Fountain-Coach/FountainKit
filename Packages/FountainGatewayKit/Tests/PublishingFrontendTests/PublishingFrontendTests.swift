import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PublishingFrontend

final class PublishingFrontendTests: XCTestCase {
    func testLoadsConfigurationFromRepositoryDefaults() throws {
        let repoRoot = Self.repositoryRoot()
        let env = ["FOUNTAINAI_ROOT": repoRoot.path]
        let config = try loadPublishingConfig(environment: env)
        XCTAssertEqual(config.port, 8085)
        XCTAssertTrue(config.rootPath.hasSuffix("/Public"), "rootPath should point at the shared Public/ directory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.rootPath))
    }

    func testEnvironmentOverrideForStaticRootWins() throws {
        let repoRoot = Self.repositoryRoot()
        let overrideRelative = "CustomPublic"
        let overridePath = repoRoot.appendingPathComponent(overrideRelative)
        try FileManager.default.createDirectory(at: overridePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: overridePath) }
        let env = [
            "FOUNTAINAI_ROOT": repoRoot.path,
            "PUBLISHING_STATIC_ROOT": overrideRelative
        ]
        let config = try loadPublishingConfig(environment: env)
        XCTAssertEqual(config.rootPath, overridePath.standardizedFileURL.path)
    }

    func testServerServesIndexHtml() async throws {
        let repoRoot = Self.repositoryRoot()
        let rootPath = repoRoot.appendingPathComponent("Public").path
        try await Task { @MainActor in
            let app = PublishingFrontend(config: PublishingConfig(port: 0, rootPath: rootPath))
            try await app.start()

            let port = app.port
            let url = URL(string: "http://127.0.0.1:\(port)/")!
            let (data, response) = try await URLSession.shared.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let html = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(html.contains("FountainKit Publishing Frontend"))

            try await app.stop()
        }.value
    }

    private static func repositoryRoot(file: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: String(describing: file))
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
