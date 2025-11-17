import XCTest
@testable import composer_score_service

final class ScoreServiceTests: XCTestCase {
    func testScoreStateDefaultsAndPatch() async throws {
        let handlers = ComposerScoreHandlers()
        // Default state
        let getOut = try await handlers.getScoreState(.init(path: .init(scoreId: "score-1")))
        guard case let .ok(ok) = getOut, case let .json(initial) = ok.body else {
            XCTFail("Expected OK JSON body"); return
        }
        XCTAssertEqual(initial.page, 1)
        XCTAssertEqual(initial.zoom, 1.0, accuracy: 0.0001)

        // Patch state
        let patch = Components.Schemas.ScoreStatePatch(page: 2, zoom: 1.5, selection: nil, annotationsVisible: true, cueFocusId: "cue-1")
        _ = try await handlers.setScoreState(.init(path: .init(scoreId: "score-1"), body: .json(patch)))

        let updatedOut = try await handlers.getScoreState(.init(path: .init(scoreId: "score-1")))
        guard case let .ok(updated) = updatedOut, case let .json(state) = updated.body else {
            XCTFail("Expected OK JSON body"); return
        }
        XCTAssertEqual(state.page, 2)
        XCTAssertEqual(state.zoom, 1.5, accuracy: 0.0001)
        XCTAssertEqual(state.annotationsVisible, true)
        XCTAssertEqual(state.cueFocusId, "cue-1")
    }
}

