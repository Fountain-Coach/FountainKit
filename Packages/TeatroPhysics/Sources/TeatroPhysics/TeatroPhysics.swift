public struct TPVec3: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
    public static let zero = TPVec3(x: 0, y: 0, z: 0)
    public static func +(lhs: TPVec3, rhs: TPVec3) -> TPVec3 {
        TPVec3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }
    public static func -(lhs: TPVec3, rhs: TPVec3) -> TPVec3 {
        TPVec3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }
    public static func *(lhs: TPVec3, rhs: Double) -> TPVec3 {
        TPVec3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
    public func dot(_ other: TPVec3) -> Double {
        x * other.x + y * other.y + z * other.z
    }
    public func length() -> Double {
        (dot(self)).squareRoot()
    }
    public func normalized() -> TPVec3 {
        let len = length()
        guard len > 0 else { return .zero }
        return self * (1.0 / len)
    }
}

public final class TPBody: @unchecked Sendable {
    public var position: TPVec3
    public var velocity: TPVec3
    public var mass: Double
    public var invMass: Double
    /// Optional half‑extents for an axis‑aligned box collider anchored at this body's position.
    /// When nil, the body is treated as a point for collision purposes.
    public var halfExtents: TPVec3?

    public init(position: TPVec3, velocity: TPVec3 = .zero, mass: Double, halfExtents: TPVec3? = nil) {
        self.position = position
        self.velocity = velocity
        self.mass = mass
        self.invMass = mass > 0 ? 1.0 / mass : 0
        self.halfExtents = halfExtents
    }
}

public protocol TPConstraint: Sendable {
    func solve(dt: Double)
}

public final class TPDistanceConstraint: TPConstraint {
    public let bodyA: TPBody
    public let bodyB: TPBody
    public let restLength: Double
    public let stiffness: Double

    public init(bodyA: TPBody, bodyB: TPBody, restLength: Double, stiffness: Double = 1.0) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.restLength = restLength
        self.stiffness = stiffness
    }

    public func solve(dt: Double) {
        let delta = bodyB.position - bodyA.position
        let dist = delta.length()
        guard dist > 1e-6 else { return }
        let diff = (dist - restLength) / dist
        let impulse = delta * (0.5 * stiffness * diff)
        if bodyA.invMass > 0 {
            bodyA.position = bodyA.position + impulse
        }
        if bodyB.invMass > 0 {
            bodyB.position = bodyB.position - impulse
        }
    }
}

public final class TPGroundConstraint: TPConstraint {
    public let body: TPBody
    public let floorY: Double

    public init(body: TPBody, floorY: Double = 0) {
        self.body = body
        self.floorY = floorY
    }

    public func solve(dt: Double) {
        _ = dt
        let halfY = body.halfExtents?.y ?? 0
        let bottomY = body.position.y - halfY
        if bottomY < floorY {
            let penetration = floorY - bottomY
            body.position.y += penetration
            if body.velocity.y < 0 {
                body.velocity.y = 0
            }
        }
    }
}

public final class TPWorld: @unchecked Sendable {
    public var bodies: [TPBody] = []
    public var constraints: [TPConstraint] = []
    public var gravity: TPVec3 = TPVec3(x: 0, y: -9.82, z: 0)
    public var linearDamping: Double = 0.02

    public init() {}

    public func addBody(_ body: TPBody) {
        bodies.append(body)
    }

    public func addConstraint(_ constraint: TPConstraint) {
        constraints.append(constraint)
    }

    public func step(dt: Double) {
        guard dt > 0 else { return }
        // Integrate forces -> velocities -> positions
        for body in bodies {
            if body.invMass == 0 { continue }
            let acceleration = gravity * body.invMass
            body.velocity = body.velocity + acceleration * dt
            // simple linear damping
            body.velocity = body.velocity * max(0, 1.0 - linearDamping)
            body.position = body.position + body.velocity * dt
        }
        // Solve constraints (single iteration for now)
        for constraint in constraints {
            constraint.solve(dt: dt)
        }
    }
}
