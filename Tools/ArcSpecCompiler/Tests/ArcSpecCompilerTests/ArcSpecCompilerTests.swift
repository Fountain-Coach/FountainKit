import XCTest
@testable import ArcSpecCompiler

final class ArcSpecCompilerTests: XCTestCase {
    func testCompileGeneratesOpenAPI() throws {
        let yaml = """
        arc: "Polyglot Hamlet – Echo Lattice"
        version: 0.1
        corpus:
          id: polyglot-hamlet
        resources:
          - id: corpus
            kind: text.corpus
            facets: [work, translation]
        operators:
          - id: echo.align
            intent: "Align semantically equivalent lines across languages."
            input:
              - {name: passages, type: "PassageRef[]", required: true}
              - {name: languages, type: "LangCode[]", required: true}
            output:
              type: EchoLattice
              guarantees: [stable ids]
        """

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let specURL = tempDir.appendingPathComponent("spec.arc.yml")
        try yaml.write(to: specURL, atomically: true, encoding: .utf8)

        let compiler = ArcSpecCompiler()
        let outputDir = tempDir.appendingPathComponent("openapi")
        let generatedURL = try compiler.compile(specURL: specURL, outputDirectory: outputDir)

        let generated = try String(contentsOf: generatedURL, encoding: .utf8)
        XCTAssertTrue(generated.contains("/echo/align"), "Expected path for operator")
        XCTAssertTrue(generated.contains("EchoAlignRequest"), "Expected request schema")
    }
}
