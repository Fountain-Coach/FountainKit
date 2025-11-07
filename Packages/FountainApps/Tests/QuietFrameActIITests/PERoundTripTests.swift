import XCTest
@testable import QuietFrameCells

/// Minimal PE adapter over CellsCore used for round-trip tests without spinning the app.
fileprivate struct PEAdapter {
    static func apply(_ props: [String: Any], to core: inout CellsCore) {
        for (k, v) in props {
            switch k {
            case "cells.grid.width": if let d = v as? Double { core.resize(width: Int(d)) }
            case "cells.grid.height": if let d = v as? Double { core.resize(height: Int(d)) }
            case "cells.grid.wrap":
                if let d = v as? Double { core.wrap = d >= 0.5 }
            case "cells.rule.name":
                if let s = v as? String { core.setRule(s) }
            case "cells.seed.hash":
                if let s = v as? String, let val = UInt64(s, radix: 16) { core.reseed(seed: val) }
            default:
                // Step Hz / run state are app concerns; ignored in core adapter
                continue
            }
        }
    }
}

final class PERoundTripTests: XCTestCase {
    func testPEGetSetRoundTrip() throws {
        var core = CellsCore(width: 16, height: 10, wrap: false, ruleName: "life", seed: 0x1)
        // Apply a set of PE-like updates
        let setProps: [String: Any] = [
            "cells.grid.width": 24.0,
            "cells.grid.height": 12.0,
            "cells.grid.wrap": 1.0,
            "cells.rule.name": "seeds",
            "cells.seed.hash": String(format: "%016llx", 0xdeadbeef)
        ]
        PEAdapter.apply(setProps, to: &core)

        // Simulate GetReply snapshot
        let numeric = core.snapshotNumeric()
        let strings = core.snapshotStrings()

        XCTAssertEqual(numeric["cells.grid.width"], 24.0)
        XCTAssertEqual(numeric["cells.grid.height"], 12.0)
        XCTAssertEqual(numeric["cells.grid.wrap"], 1.0)
        XCTAssertEqual(strings["cells.rule.name"], "seeds")
        XCTAssertEqual(strings["cells.seed.kind"], "hash")
        XCTAssertEqual(strings["cells.seed.hash"], String(format: "%016llx", 0xdeadbeef))
        XCTAssertNotNil(strings["cells.state.hash"]) // present

        // Advance a few ticks and ensure state hash evolves deterministically
        let h0 = core.stateHash
        for _ in 0..<5 { _ = core.tick() }
        let h1 = core.stateHash
        XCTAssertNotEqual(h0, h1)
    }

    func testNotifyThenGetSequence() throws {
        var core = CellsCore(width: 20, height: 12, wrap: true, ruleName: "life", seed: 0x100)
        let beforeNum = core.snapshotNumeric()
        let beforeStr = core.snapshotStrings()

        // Simulate PE Set for a grid resize and rule change
        let setProps: [String: Any] = [
            "cells.grid.width": 28.0,
            "cells.grid.height": 14.0,
            "cells.rule.name": "highlife"
        ]
        PEAdapter.apply(setProps, to: &core)

        // "Notify" effect: values must have changed compared to before
        let afterNum = core.snapshotNumeric()
        let afterStr = core.snapshotStrings()

        XCTAssertNotEqual(beforeNum["cells.grid.width"], afterNum["cells.grid.width"])
        XCTAssertNotEqual(beforeNum["cells.grid.height"], afterNum["cells.grid.height"])
        XCTAssertEqual(afterStr["cells.rule.name"], "highlife")

        // "GetReply" should match current snapshot
        XCTAssertEqual(afterNum["cells.grid.width"], 28.0)
        XCTAssertEqual(afterNum["cells.grid.height"], 14.0)
        XCTAssertEqual(afterStr["cells.rule.name"], "highlife")

        // State hash presence and stability across immediate get
        XCTAssertNotNil(afterStr["cells.state.hash"])
        let h0 = core.stateHash
        let h1 = core.stateHash
        XCTAssertEqual(h0, h1)
    }
}
