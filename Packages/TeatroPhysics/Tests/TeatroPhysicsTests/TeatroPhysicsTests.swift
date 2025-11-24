import XCTest
@testable import TeatroPhysics

final class TeatroPhysicsTests: XCTestCase {
    func testFreeFallMovesDownwards() {
        let world = TPWorld()
        let body = TPBody(position: TPVec3(x: 0, y: 0, z: 0), mass: 1.0)
        world.addBody(body)
        world.gravity = TPVec3(x: 0, y: -10, z: 0)
        world.linearDamping = 0

        world.step(dt: 0.1)
        XCTAssertLessThan(body.position.y, 0)
    }

    func testDistanceConstraintKeepsBodiesClose() {
        let world = TPWorld()
        let a = TPBody(position: TPVec3(x: 0, y: 0, z: 0), mass: 1.0)
        let b = TPBody(position: TPVec3(x: 2, y: 0, z: 0), mass: 1.0)
        world.addBody(a)
        world.addBody(b)
        let restLength = 1.0
        let constraint = TPDistanceConstraint(bodyA: a, bodyB: b, restLength: restLength, stiffness: 1.0)
        world.addConstraint(constraint)

        for _ in 0..<10 {
            world.step(dt: 0.016)
        }

        let dist = (b.position - a.position).length()
        XCTAssertLessThan(abs(dist - restLength), 0.2)
    }
}

