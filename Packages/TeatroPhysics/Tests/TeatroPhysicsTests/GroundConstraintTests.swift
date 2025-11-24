import XCTest
@testable import TeatroPhysics

final class GroundConstraintTests: XCTestCase {
    func testBodyDoesNotFallBelowFloor() {
        let world = TPWorld()
        let body = TPBody(position: TPVec3(x: 0, y: -1, z: 0), mass: 1)
        world.addBody(body)
        world.addConstraint(TPGroundConstraint(body: body, floorY: 0))

        world.step(dt: 0.1)
        XCTAssertGreaterThanOrEqual(body.position.y, 0)
    }

    func testGroundConstraintZeroesDownwardVelocityAtFloor() {
        let world = TPWorld()
        let body = TPBody(position: TPVec3(x: 0, y: -0.5, z: 0), mass: 1)
        body.velocity = TPVec3(x: 0, y: -5, z: 0)
        world.addBody(body)
        world.addConstraint(TPGroundConstraint(body: body, floorY: 0))

        world.step(dt: 0.1)

        XCTAssertGreaterThanOrEqual(body.position.y, 0)
        XCTAssertGreaterThanOrEqual(body.velocity.y, 0)
    }
}
