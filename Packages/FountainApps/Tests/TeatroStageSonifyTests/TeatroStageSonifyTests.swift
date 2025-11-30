import XCTest
@testable import teatro_stage_sonify_support
import TeatroPhysics

final class TeatroStageSonifyTests: XCTestCase {
    func testSonifyTickProducesFiniteValues() {
        let rig = TPPuppetRig()
        var state = SonifyState(
            time: 0,
            lastSnap: rig.snapshot(),
            lastEnergy: EnergySnapshot(time: 0, barHeight: 15, limbEnergy: 0),
            tickCount: 0
        )
        for _ in 0..<120 {
            let out = sonifyTick(state: &state, rig: rig, dt: 1.0 / 60.0)
            XCTAssert(out.freq.isFinite && out.freq > 0)
            XCTAssert(out.gain.isFinite && out.gain >= 0)
            XCTAssert(out.energy.isFinite && out.energy >= 0)
        }
    }
}
