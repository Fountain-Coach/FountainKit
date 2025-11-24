import SwiftUI
import MetalViewKit
import TeatroPhysicsBullet
import QuartzCore
#if canImport(AppKit)
import AppKit
#endif

@main
struct TeatroBulletApp: App {
    var body: some Scene {
        WindowGroup("Teatro Bullet Stage") {
            TeatroBulletView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

struct TeatroBulletView: View {
    @State private var zoom: CGFloat = 1.0
    @State private var translation: CGPoint = .zero
    @State private var bulletBodies: [TeatroStageMetalNode.BulletBodyRender] = []
    @State private var cameraAzimuth: CGFloat = .pi / 4
    @State private var scenario: Int = 1
    @State private var hud: String = "1: ball+box  2: stack  3: chain (stub)  A/D orbit  W/S zoom  R reset"
    @State private var debug: String = ""

    var body: some View {
        GeometryReader { geo in
            MetalCanvasView(
                zoom: zoom,
                translation: translation,
                nodes: {
                    let frame = CGRect(origin: .zero, size: geo.size)
                    let scene = TeatroStageScene(
                        camera: TeatroCameraState(azimuth: cameraAzimuth, zoom: zoom),
                        roomSize: TeatroVec3(x: 15, y: 10, z: 15)
                    )
                    let node = TeatroStageMetalNode(
                        id: "teatro-bullet-stage",
                        frameDoc: frame,
                        scene: scene
                    )
                    node.showRoomGrid = true
                    node.bulletBodies = bulletBodies
                    node.hudText = hud
                    node.debugText = debug
                    return [node]
                },
                selected: { [] },
                onSelect: { _ in },
                onMoveBy: { _,_ in },
                onTransformChanged: { t, z in
                    translation = t
                    zoom = z
                }
            )
            .task {
                await runBulletLoop()
            }
            .onAppear {
                installKeyMonitor()
            }
        }
    }

    private func runBulletLoop() async {
        var currentScenario = scenario
        var world = BulletWorld(gravity: BulletVec3(x: 0, y: -9.81, z: 0))
        _ = world.addStaticPlane(normal: BulletVec3(x: 0, y: 1, z: 0), constant: 0)
        var bodies = makeBodies(for: scenario, world: &world)

        var last = CACurrentMediaTime()
        let fixed: Double = 1.0 / 240.0

        while true {
            let now = CACurrentMediaTime()
            let dt = max(0.0, now - last)
            last = now

            if currentScenario != scenario {
                world = BulletWorld(gravity: BulletVec3(x: 0, y: -9.81, z: 0))
                _ = world.addStaticPlane(normal: BulletVec3(x: 0, y: 1, z: 0), constant: 0)
                bodies = makeBodies(for: scenario, world: &world)
                currentScenario = scenario
            }

            world.step(timeStep: dt, maxSubSteps: 4, fixedTimeStep: fixed)

            let rendered = bodies.enumerated().map { index, body -> TeatroStageMetalNode.BulletBodyRender in
                let pos = body.position
                switch scenario {
                case 2:
                    return .init(
                        position: .init(x: CGFloat(pos.x), y: CGFloat(pos.y), z: CGFloat(pos.z)),
                        shape: .box(halfExtents: .init(x: 0.6, y: 0.6, z: 0.6))
                    )
                default:
                    if index == 0 {
                        return .init(
                            position: .init(x: CGFloat(pos.x), y: CGFloat(pos.y), z: CGFloat(pos.z)),
                            shape: .sphere(radius: 0.8)
                        )
                    } else {
                        return .init(
                            position: .init(x: CGFloat(pos.x), y: CGFloat(pos.y), z: CGFloat(pos.z)),
                            shape: .box(halfExtents: .init(x: 0.8, y: 0.8, z: 0.8))
                        )
                    }
                }
            }

            await MainActor.run {
                bulletBodies = rendered
                debug = String(format: "az=%.2f zoom=%.2f bodies=%d", cameraAzimuth, zoom, rendered.count)
            }

            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private func makeBodies(for scenario: Int, world: inout BulletWorld) -> [BulletBody] {
        switch scenario {
        case 2:
            return [
                world.addBox(halfExtents: BulletVec3(x: 0.6, y: 0.6, z: 0.6), mass: 2.0, position: BulletVec3(x: 0.0, y: 6.0, z: 0.0)),
                world.addBox(halfExtents: BulletVec3(x: 0.6, y: 0.6, z: 0.6), mass: 2.0, position: BulletVec3(x: 0.0, y: 8.0, z: 0.0)),
                world.addBox(halfExtents: BulletVec3(x: 0.6, y: 0.6, z: 0.6), mass: 2.0, position: BulletVec3(x: 0.0, y: 10.0, z: 0.0))
            ]
        default:
            return [
                world.addSphere(radius: 0.8, mass: 1.0, position: BulletVec3(x: 0, y: 8, z: 0)),
                world.addBox(halfExtents: BulletVec3(x: 0.8, y: 0.8, z: 0.8), mass: 2.0, position: BulletVec3(x: 2.0, y: 10, z: 0.5))
            ]
        }
    }

    #if canImport(AppKit)
    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        switch event.keyCode {
        case 12: // q
            NSApplication.shared.terminate(nil)
        case 0: // a
            cameraAzimuth -= 0.12
        case 2: // d
            cameraAzimuth += 0.12
        case 13: // w
            zoom = min(3.0, zoom * 1.05)
        case 1: // s
            zoom = max(0.3, zoom * 0.95)
        case 15: // r
            scenario = scenario // trigger reset via loop check
        case 18: // 1
            scenario = 1
        case 19: // 2
            scenario = 2
        case 20: // 3
            scenario = 3
        default:
            break
        }
    }
    #endif
}
