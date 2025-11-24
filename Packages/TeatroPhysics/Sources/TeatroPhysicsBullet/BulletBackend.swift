import Foundation
import TeatroPhysics
import BulletShim

public struct BulletVec3: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public final class BulletBody: @unchecked Sendable {
    let raw: UnsafeMutablePointer<BulletRigidBody>
    init(raw: UnsafeMutablePointer<BulletRigidBody>) {
        self.raw = raw
    }

    public var position: BulletVec3 {
        var x = 0.0, y = 0.0, z = 0.0
        BulletGetBodyPosition(raw, &x, &y, &z)
        return BulletVec3(x: x, y: y, z: z)
    }

    public var linearVelocity: BulletVec3 {
        var x = 0.0, y = 0.0, z = 0.0
        BulletGetBodyLinearVelocity(raw, &x, &y, &z)
        return BulletVec3(x: x, y: y, z: z)
    }

    public var isActive: Bool {
        BulletBodyIsActive(raw) == 1
    }
}

public final class BulletWorld: @unchecked Sendable {
    private let raw: UnsafeMutablePointer<BulletWorld>
    public init(gravity: BulletVec3 = BulletVec3(x: 0, y: -9.81, z: 0)) {
        guard let w = BulletCreateWorld(gravity.x, gravity.y, gravity.z) else {
            fatalError("BulletCreateWorld returned nil")
        }
        self.raw = w
    }

    deinit {
        BulletDestroyWorld(raw)
    }

    @discardableResult
    public func addStaticPlane(normal: BulletVec3 = BulletVec3(x: 0, y: 1, z: 0), constant: Double = 0) -> BulletBody {
        guard let body = BulletCreateStaticPlane(raw, normal.x, normal.y, normal.z, constant) else {
            fatalError("BulletCreateStaticPlane failed")
        }
        return BulletBody(raw: body)
    }

    @discardableResult
    public func addSphere(radius: Double, mass: Double, position: BulletVec3) -> BulletBody {
        guard let body = BulletCreateSphere(raw, radius, mass, position.x, position.y, position.z) else {
            fatalError("BulletCreateSphere failed")
        }
        return BulletBody(raw: body)
    }

    @discardableResult
    public func addBox(halfExtents: BulletVec3, mass: Double, position: BulletVec3) -> BulletBody {
        guard let body = BulletCreateBox(raw, halfExtents.x, halfExtents.y, halfExtents.z, mass, position.x, position.y, position.z) else {
            fatalError("BulletCreateBox failed")
        }
        return BulletBody(raw: body)
    }

    public func step(timeStep: Double, maxSubSteps: Int = 4, fixedTimeStep: Double = 1.0 / 240.0) {
        BulletStepWorld(raw, timeStep, Int32(maxSubSteps), fixedTimeStep)
    }
}
