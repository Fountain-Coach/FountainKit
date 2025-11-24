import Foundation
import SDLKit
import TeatroPhysicsBullet
#if canImport(CSDL3)
import CSDL3
#endif

private struct BodyViz {
    let id: String
    let body: BulletBody
    let radius: Double?
    let halfExtents: BulletVec3?
    let color: UInt32
}

@main
@MainActor
struct BulletPhysicsInstrument {
    static func main() {
#if !canImport(CSDL3)
        fputs("bullet-physics-instrument requires SDL3; CSDL3 not available.\n", stderr)
        return
#else
        do {
            let width = 1280
            let height = 800
            let window = SDLWindow(config: .init(title: "Bullet Physics Instrument", width: width, height: height))
            try window.open()
            try window.show()
            let renderer = try SDLRenderer(width: width, height: height, window: window)

            var running = true
            var cameraAzimuth: CGFloat = .pi / 4
            var zoom: CGFloat = 1.0

            let world = BulletWorld(gravity: BulletVec3(x: 0, y: -9.81, z: 0))
            let _ = world.addStaticPlane(normal: BulletVec3(x: 0, y: 1, z: 0), constant: 0)

            let ball = world.addSphere(radius: 0.6, mass: 1.0, position: BulletVec3(x: 0, y: 6, z: 0))
            let box = world.addBox(halfExtents: BulletVec3(x: 0.6, y: 0.6, z: 0.6), mass: 2.0, position: BulletVec3(x: 1.8, y: 8, z: 0.4))

            var bodies: [BodyViz] = [
                BodyViz(id: "ball", body: ball, radius: 0.6, halfExtents: nil, color: 0xFF111111),
                BodyViz(id: "box", body: box, radius: nil, halfExtents: BulletVec3(x: 0.6, y: 0.6, z: 0.6), color: 0xFF444444)
            ]

            let fps: Double = 60
            let frameTime: useconds_t = useconds_t(1_000_000.0 / fps)
            let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.65)

            while running {
                var event = SDLKit_Event(type: 0, x: 0, y: 0, keycode: 0, button: 0)
                while SDLKit_PollEvent(&event) != 0 {
                    let type = Int32(bitPattern: event.type)
                    let key = event.keycode
                    let keyQ: Int32 = 113  // 'q'
                    let keyA: Int32 = 97   // 'a'
                    let keyD: Int32 = 100  // 'd'
                    let keyW: Int32 = 119  // 'w'
                    let keyS: Int32 = 115  // 's'
                    let keyR: Int32 = 114  // 'r'
                    switch type {
                    case Int32(SDLKIT_EVENT_QUIT),
                         Int32(SDLKIT_EVENT_WINDOW_CLOSED):
                        running = false
                    case Int32(SDLKIT_EVENT_KEY_DOWN):
                        if key == keyQ {
                            running = false
                        } else if key == keyA {
                            cameraAzimuth -= 0.1
                        } else if key == keyD {
                            cameraAzimuth += 0.1
                        } else if key == keyW {
                            zoom = min(3.0, zoom * 1.05)
                        } else if key == keyS {
                            zoom = max(0.3, zoom * 0.95)
                        } else if key == keyR {
                            reset(world: world, bodies: &bodies)
                        }
                    default:
                        break
                    }
                }

                world.step(timeStep: 1.0 / fps, maxSubSteps: 4, fixedTimeStep: 1.0 / 240.0)

                try renderer.clear(color: 0xFFF4EAD6)
                drawRoom(renderer: renderer, cameraAzimuth: cameraAzimuth, zoom: zoom, center: center)
                drawBodies(renderer: renderer, bodies: bodies, cameraAzimuth: cameraAzimuth, zoom: zoom, center: center)

                renderer.present()
                usleep(frameTime)
            }

            renderer.shutdown()
            window.close()
        } catch {
            fputs("bullet-physics-instrument failed: \(error)\n", stderr)
        }
#endif
    }

    private static func reset(world: BulletWorld, bodies: inout [BodyViz]) {
        // Recreate simple scene
        bodies.removeAll()
        let ball = world.addSphere(radius: 0.6, mass: 1.0, position: BulletVec3(x: 0, y: 6, z: 0))
        let box = world.addBox(halfExtents: BulletVec3(x: 0.6, y: 0.6, z: 0.6), mass: 2.0, position: BulletVec3(x: 1.8, y: 8, z: 0.4))
        bodies.append(BodyViz(id: "ball", body: ball, radius: 0.6, halfExtents: nil, color: 0xFF111111))
        bodies.append(BodyViz(id: "box", body: box, radius: nil, halfExtents: BulletVec3(x: 0.6, y: 0.6, z: 0.6), color: 0xFF444444))
    }

    private static func rotateY(_ p: BulletVec3, azimuth: CGFloat) -> BulletVec3 {
        let c = cos(azimuth)
        let s = sin(azimuth)
        return BulletVec3(
            x: p.x * Double(c) - p.z * Double(s),
            y: p.y,
            z: p.x * Double(s) + p.z * Double(c)
        )
    }

    private static func isoProject(_ p: BulletVec3, center: CGPoint, zoom: CGFloat) -> CGPoint {
        let scale: CGFloat = 13.0 * zoom
        let u = (CGFloat(p.x) - CGFloat(p.z)) * scale
        let v = (CGFloat(p.x) + CGFloat(p.z)) * scale * 0.5 - CGFloat(p.y) * scale
        return CGPoint(x: center.x + u, y: center.y + v)
    }

    private static func drawRoom(renderer: SDLRenderer, cameraAzimuth: CGFloat, zoom: CGFloat, center: CGPoint) {
        let floorHalfW: CGFloat = 6
        let floorHalfD: CGFloat = 6

        func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            let world = BulletVec3(x: Double(x), y: Double(y), z: Double(z))
            let rotated = rotateY(world, azimuth: cameraAzimuth)
            return isoProject(rotated, center: center, zoom: zoom)
        }

        let floor: [CGPoint] = [
            project(-floorHalfW, 0, -floorHalfD),
            project(floorHalfW, 0, -floorHalfD),
            project(floorHalfW, 0, floorHalfD),
            project(-floorHalfW, 0, floorHalfD)
        ]
        let color: UInt32 = 0xFF111111
        try? renderer.drawLine(x1: Int(floor[0].x), y1: Int(floor[0].y), x2: Int(floor[1].x), y2: Int(floor[1].y), color: color)
        try? renderer.drawLine(x1: Int(floor[1].x), y1: Int(floor[1].y), x2: Int(floor[2].x), y2: Int(floor[2].y), color: color)
        try? renderer.drawLine(x1: Int(floor[2].x), y1: Int(floor[2].y), x2: Int(floor[3].x), y2: Int(floor[3].y), color: color)
        try? renderer.drawLine(x1: Int(floor[3].x), y1: Int(floor[3].y), x2: Int(floor[0].x), y2: Int(floor[0].y), color: color)
    }

    private static func drawBodies(renderer: SDLRenderer,
                                   bodies: [BodyViz],
                                   cameraAzimuth: CGFloat,
                                   zoom: CGFloat,
                                   center: CGPoint) {
        for viz in bodies {
            let pos = viz.body.position
            if let r = viz.radius {
                let segments = 18
                var prev = isoProject(rotateY(BulletVec3(x: pos.x + r, y: pos.y, z: pos.z), azimuth: cameraAzimuth), center: center, zoom: zoom)
                for i in 1...segments {
                    let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
                    let world = BulletVec3(
                        x: pos.x + r * cos(Double(angle)),
                        y: pos.y,
                        z: pos.z + r * sin(Double(angle))
                    )
                    let pt = isoProject(rotateY(world, azimuth: cameraAzimuth), center: center, zoom: zoom)
                    try? renderer.drawLine(x1: Int(prev.x), y1: Int(prev.y), x2: Int(pt.x), y2: Int(pt.y), color: viz.color)
                    prev = pt
                }
            } else if let half = viz.halfExtents {
                // Draw top square for simplicity (axis-aligned in world)
                let corners: [BulletVec3] = [
                    BulletVec3(x: pos.x - half.x, y: pos.y + half.y, z: pos.z - half.z),
                    BulletVec3(x: pos.x + half.x, y: pos.y + half.y, z: pos.z - half.z),
                    BulletVec3(x: pos.x + half.x, y: pos.y + half.y, z: pos.z + half.z),
                    BulletVec3(x: pos.x - half.x, y: pos.y + half.y, z: pos.z + half.z)
                ]
                var projected = corners.map { isoProject(rotateY($0, azimuth: cameraAzimuth), center: center, zoom: zoom) }
                projected.append(projected.first!)
                for i in 0..<(projected.count - 1) {
                    try? renderer.drawLine(x1: Int(projected[i].x), y1: Int(projected[i].y),
                                           x2: Int(projected[i+1].x), y2: Int(projected[i+1].y),
                                           color: viz.color)
                }
            }
        }
    }

}
