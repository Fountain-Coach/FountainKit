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

    func testCompileTheFourStarsSpeechAtlas() throws {
        let yaml = """
        arc: "The Four Stars – Speech Atlas"
        version: 0.1
        corpus:
          id: the-four-stars
          refs:
            - type: fountain-manifest
              url: fountain-manifest://.fountain/seeding/the-four-stars/seed-manifest.json
            - type: git
              url: https://github.com/Fountain-Coach/the-four-stars
        resources:
          - id: speeches
            kind: text.speech
            facets: [act, scene, speaker, location, index]
          - id: manifest
            kind: metadata.seed-manifest
            facets: [document, translation, annotation, audio]
        operators:
          - id: speeches.list
            intent: "List speeches filtered by act, scene, or speaker."
            input:
              - {name: act, type: ActCode, required: false}
              - {name: scene, type: SceneCode, required: false}
              - {name: speaker, type: SpeakerID, required: false}
              - {name: limit, type: Int, default: 100}
              - {name: offset, type: Int, default: 0}
            output:
              type: SpeechList
              guarantees:
                - stable ordering
                - idempotent queries
          - id: speeches.detail
            intent: "Return a single speech with surrounding context."
            input:
              - {name: speech_id, type: SpeechID, required: true}
              - {name: include_context, type: Bool, default: true}
            output:
              type: SpeechDetail
              guarantees:
                - canonical text
                - includes metadata
          - id: speeches.summary
            intent: "Summarise a set of speeches and surface recurring speakers."
            input:
              - {name: speech_ids, type: "SpeechID[]", required: true}
              - {name: max_speakers, type: Int, default: 5}
            output:
              type: SpeechSummary
              guarantees:
                - cites source speeches
                - deterministic for identical inputs
        policies:
          execution:
            network: deny
            cpu_seconds: 30
            memory_mb: 512
          artifacts:
            base_path: /data/corpora/the-four-stars/studios/speech-atlas
        """

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let specURL = tempDir.appendingPathComponent("speech-atlas.arc.yml")
        try yaml.write(to: specURL, atomically: true, encoding: .utf8)

        let compiler = ArcSpecCompiler()
        let outputDir = tempDir.appendingPathComponent("openapi")
        let generatedURL = try compiler.compile(specURL: specURL, outputDirectory: outputDir)

        let generated = try String(contentsOf: generatedURL, encoding: .utf8)
        XCTAssertTrue(generated.contains("/speeches/list"), "Expected path for list operator")
        XCTAssertTrue(generated.contains("/speeches/detail"), "Expected path for detail operator")
        XCTAssertTrue(generated.contains("/speeches/summary"), "Expected path for summary operator")
    }
}
