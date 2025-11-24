import Foundation
import TeatroPhysicsBullet

/// Minimal Bullet-backed physics demo with no UI.
/// Runs a few scripted steps and prints body positions for quick verification.
@main
struct BulletPhysicsDemo {
    static func main() {
        let world = BulletWorld(gravity: BulletVec3(x: 0, y: -9.81, z: 0))
        _ = world.addStaticPlane(normal: BulletVec3(x: 0, y: 1, z: 0), constant: 0)

        let ball = world.addSphere(radius: 0.5, mass: 1.0, position: BulletVec3(x: 0, y: 5, z: 0))
        let box = world.addBox(halfExtents: BulletVec3(x: 0.5, y: 0.5, z: 0.5),
                               mass: 2.0,
                               position: BulletVec3(x: 1.5, y: 8, z: 0))

        let dt = 1.0 / 60.0
        for step in 0..<180 {
            world.step(timeStep: dt, maxSubSteps: 4, fixedTimeStep: dt / 2.0)
            let t = Double(step + 1) * dt
            let bp = ball.position
            let bv = ball.linearVelocity
            let xp = box.position
            if step % 10 == 0 {
                print(String(format: "t=%.3f ball pos=(%.3f, %.3f, %.3f) vel=(%.3f, %.3f, %.3f) | box pos=(%.3f, %.3f, %.3f) active=%d",
                             t,
                             bp.x, bp.y, bp.z,
                             bv.x, bv.y, bv.z,
                             xp.x, xp.y, xp.z,
                             box.isActive ? 1 : 0))
            }
        }
        print("Done. Bodies at rest? ball active=\(ball.isActive) box active=\(box.isActive)")
    }
}
