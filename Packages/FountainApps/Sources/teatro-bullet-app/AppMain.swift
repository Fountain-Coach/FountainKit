import SwiftUI
import MetalViewKit
import TeatroPhysicsBullet
import QuartzCore

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
                    node.bulletBodies = bulletBodies
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
        }
    }

    private func runBulletLoop() async {
        let world = BulletWorld(gravity: BulletVec3(x: 0, y: -9.81, z: 0))
        _ = world.addStaticPlane(normal: BulletVec3(x: 0, y: 1, z: 0), constant: 0)
        let sphere = world.addSphere(radius: 0.8, mass: 1.0, position: BulletVec3(x: 0, y: 8, z: 0))
        let box = world.addBox(halfExtents: BulletVec3(x: 0.8, y: 0.8, z: 0.8), mass: 2.0, position: BulletVec3(x: 2.0, y: 10, z: 0.5))

        var last = CACurrentMediaTime()
        let fixed: Double = 1.0 / 240.0

        while true {
            let now = CACurrentMediaTime()
            let dt = max(0.0, now - last)
            last = now
            world.step(timeStep: dt, maxSubSteps: 4, fixedTimeStep: fixed)

            let spherePose = TeatroStageMetalNode.BulletBodyRender(
                position: .init(x: CGFloat(sphere.position.x), y: CGFloat(sphere.position.y), z: CGFloat(sphere.position.z)),
                shape: .sphere(radius: 0.8)
            )
            let boxPose = TeatroStageMetalNode.BulletBodyRender(
                position: .init(x: CGFloat(box.position.x), y: CGFloat(box.position.y), z: CGFloat(box.position.z)),
                shape: .box(halfExtents: .init(x: 0.8, y: 0.8, z: 0.8))
            )

            await MainActor.run {
                bulletBodies = [spherePose, boxPose]
            }

            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }
}
