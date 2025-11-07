import XCTest
@testable import QuietFrameCells

final class ActIITests: XCTestCase {
    func testDeterministicStateHashSameSeed() throws {
        var a = CellsCore(width: 32, height: 20, wrap: true, ruleName: "life", seed: 0x1234)
        var b = CellsCore(width: 32, height: 20, wrap: true, ruleName: "life", seed: 0x1234)
        for _ in 0..<25 { _ = a.tick() }
        for _ in 0..<25 { _ = b.tick() }
        XCTAssertEqual(a.stateHash, b.stateHash)
    }

    func testDifferentSeedUsuallyDifferentHash() throws {
        var a = CellsCore(width: 32, height: 20, wrap: true, ruleName: "life", seed: 0x1)
        var b = CellsCore(width: 32, height: 20, wrap: true, ruleName: "life", seed: 0x2)
        for _ in 0..<10 { _ = a.tick(); _ = b.tick() }
        XCTAssertNotEqual(a.stateHash, b.stateHash)
    }

    func testRuleSelectionAffectsEvolution() throws {
        var a = CellsCore(width: 24, height: 16, wrap: true, ruleName: "life", seed: 0xdeadbeef)
        var b = CellsCore(width: 24, height: 16, wrap: true, ruleName: "seeds", seed: 0xdeadbeef)
        for _ in 0..<5 { _ = a.tick(); _ = b.tick() }
        XCTAssertNotEqual(a.stateHash, b.stateHash)
    }
}

