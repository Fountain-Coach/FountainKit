import XCTest
@testable import TeatroPhysics

final class PuppetRigMechanicsTests: XCTestCase {
    private let epsilonPos: Double = 0.05
    private let epsilonSym: Double = 0.05

    func testRestPoseMatchesSpecCoordinates() {
        let rig = TPPuppetRig()
        let snap = rig.snapshot()

        // Positions as specified in spec/rig-puppet/mechanics.md
        XCTAssertEqual(snap.controller.x, 0, accuracy: epsilonPos)
        XCTAssertEqual(snap.controller.y, 19, accuracy: epsilonPos)
        XCTAssertEqual(snap.controller.z, 0, accuracy: epsilonPos)

        XCTAssertEqual(snap.bar.x, 0, accuracy: epsilonPos)
        XCTAssertEqual(snap.bar.y, 15, accuracy: epsilonPos)
        XCTAssertEqual(snap.bar.z, 0, accuracy: epsilonPos)

        XCTAssertEqual(snap.torso.x, 0, accuracy: epsilonPos)
        XCTAssertEqual(snap.torso.y, 8, accuracy: epsilonPos)
        XCTAssertEqual(snap.torso.z, 0, accuracy: epsilonPos)

        XCTAssertEqual(snap.head.x, 0, accuracy: epsilonPos)
        XCTAssertEqual(snap.head.y, 10, accuracy: epsilonPos)
        XCTAssertEqual(snap.head.z, 0, accuracy: epsilonPos)

        XCTAssertEqual(snap.handL.x, -1.8, accuracy: epsilonPos)
        XCTAssertEqual(snap.handL.y, 8, accuracy: epsilonPos)
        XCTAssertEqual(snap.handL.z, 0, accuracy: epsilonPos)

        XCTAssertEqual(snap.handR.x, 1.8, accuracy: epsilonPos)
        XCTAssertEqual(snap.handR.y, 8, accuracy: epsilonPos)
        XCTAssertEqual(snap.handR.z, 0, accuracy: epsilonPos)

        XCTAssertEqual(snap.footL.x, -0.6, accuracy: epsilonPos)
        XCTAssertEqual(snap.footL.y, 5, accuracy: epsilonPos)
        XCTAssertEqual(snap.footL.z, 0, accuracy: epsilonPos)

        XCTAssertEqual(snap.footR.x, 0.6, accuracy: epsilonPos)
        XCTAssertEqual(snap.footR.y, 5, accuracy: epsilonPos)
        XCTAssertEqual(snap.footR.z, 0, accuracy: epsilonPos)

        // Symmetry checks
        XCTAssertEqual(snap.handL.x, -snap.handR.x, accuracy: epsilonSym)
        XCTAssertEqual(snap.footL.x, -snap.footR.x, accuracy: epsilonSym)
        XCTAssertEqual(snap.head.x, snap.torso.x, accuracy: epsilonSym)
    }

    func testRestPoseVerticalOrdering() {
        let rig = TPPuppetRig()
        let snap = rig.snapshot()
        XCTAssertGreaterThan(snap.controller.y, snap.bar.y)
        XCTAssertGreaterThan(snap.bar.y, snap.head.y)
        XCTAssertGreaterThan(snap.head.y, snap.torso.y)
        XCTAssertGreaterThanOrEqual(snap.footL.y, 0)
        XCTAssertGreaterThanOrEqual(snap.footR.y, 0)
    }

    func testControllerMovesWithinBoundsAndKeepsStructure() {
        let rig = TPPuppetRig()
        var t: Double = 0
        let dt = 1.0 / 60.0
        for _ in 0..<60 {
            t += dt
            rig.step(dt: dt, time: t)
        }
        let snap = rig.snapshot()
        XCTAssertLessThanOrEqual(abs(snap.controller.x), 2.0 + 1e-3)

        // Controller may drift under gravity; assert a looser but explicit bound.
        XCTAssertGreaterThanOrEqual(snap.controller.y, 15.0 - 1e-3)
        XCTAssertLessThanOrEqual(snap.controller.y, 19.5 + 1e-3)

        // Vertical ordering still holds after motion.
        XCTAssertGreaterThan(snap.controller.y, snap.bar.y)
        XCTAssertGreaterThan(snap.bar.y, snap.head.y)
        XCTAssertGreaterThan(snap.head.y, snap.torso.y)
        XCTAssertGreaterThanOrEqual(snap.footL.y, 0)
        XCTAssertGreaterThanOrEqual(snap.footR.y, 0)

        // Feet corridor
        XCTAssertLessThanOrEqual(abs(snap.footL.x), 2.0 + 1e-3)
        XCTAssertLessThanOrEqual(abs(snap.footR.x), 2.0 + 1e-3)

        // Torso support: torso over the feet (in X)
        let minFootX = min(snap.footL.x, snap.footR.x) - 0.5
        let maxFootX = max(snap.footL.x, snap.footR.x) + 0.5
        XCTAssertGreaterThanOrEqual(snap.torso.x, minFootX - 1e-3)
        XCTAssertLessThanOrEqual(snap.torso.x, maxFootX + 1e-3)

        // Head under controller (limited lateral drift)
        XCTAssertLessThanOrEqual(abs(snap.head.x - snap.controller.x), 3.0 + 1e-3)
    }

    func testStringsStayWithinStretchBand() {
        let rig = TPPuppetRig()
        let rest = rig.snapshot()

        func length(_ a: TPVec3, _ b: TPVec3) -> Double {
            (b - a).length()
        }

        let restControllerBar = length(rest.controller, rest.bar)
        let restControllerHandL = length(rest.controller, rest.handL)
        let restControllerHandR = length(rest.controller, rest.handR)
        let restBarHead = length(rest.bar, rest.head)

        var t: Double = 0
        let dt = 1.0 / 60.0
        for _ in 0..<60 {
            t += dt
            rig.step(dt: dt, time: t)
            let snap = rig.snapshot()

            let currentControllerBar = length(snap.controller, snap.bar)
            let currentControllerHandL = length(snap.controller, snap.handL)
            let currentControllerHandR = length(snap.controller, snap.handR)
            let currentBarHead = length(snap.bar, snap.head)

            // Stretch band 0.8x .. 1.2x
            XCTAssertBetween(currentControllerBar, min: 0.8 * restControllerBar, max: 1.2 * restControllerBar)
            XCTAssertBetween(currentControllerHandL, min: 0.8 * restControllerHandL, max: 1.2 * restControllerHandL)
            XCTAssertBetween(currentControllerHandR, min: 0.8 * restControllerHandR, max: 1.2 * restControllerHandR)
            XCTAssertBetween(currentBarHead, min: 0.8 * restBarHead, max: 1.2 * restBarHead)

            // No slack: never less than half rest length
            XCTAssertGreaterThanOrEqual(currentControllerBar, 0.5 * restControllerBar)
            XCTAssertGreaterThanOrEqual(currentControllerHandL, 0.5 * restControllerHandL)
            XCTAssertGreaterThanOrEqual(currentControllerHandR, 0.5 * restControllerHandR)
            XCTAssertGreaterThanOrEqual(currentBarHead, 0.5 * restBarHead)
        }
    }

    // MARK: - Helpers

    private func XCTAssertBetween(_ value: Double, min: Double, max: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(value, min - 1e-6, file: file, line: line)
        XCTAssertLessThanOrEqual(value, max + 1e-6, file: file, line: line)
    }
}
