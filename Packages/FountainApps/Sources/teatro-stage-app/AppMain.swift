import SwiftUI
import MetalViewKit
import TeatroPhysics

@main
struct TeatroStageApp: App {
    var body: some Scene {
        WindowGroup("Teatro Stage") {
            TeatroStageView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

struct TeatroStageView: View {
    @State private var scene = TeatroStageScene(
        camera: TeatroCameraState(azimuth: 0.0, zoom: 1.0),
        roomSize: TeatroVec3(x: 10, y: 5, z: 10),
        reps: [
            TeatroRep(id: "client", position: TeatroVec3(x: -0.3, y: 0, z: 0.2), roleLabel: "Client"),
            TeatroRep(id: "mother", position: TeatroVec3(x: 0.4, y: 0, z: -0.1), roleLabel: "Mother")
        ],
        lights: [
            TeatroLight(
                id: "spot-center",
                type: .spot,
                origin: TeatroVec3(x: 0, y: 4, z: 0),
                target: TeatroVec3(x: 0, y: 0, z: 0),
                radius: 3.0,
                intensity: 1.0,
                label: "Center Spot"
            )
        ]
    )
    @State private var zoom: CGFloat = 1.0
    @State private var translation: CGPoint = .zero
    @State private var puppetPose: TeatroStageMetalNode.TeatroPuppetPose?
    @State private var ballPosition: TeatroVec3?

    var body: some View {
        GeometryReader { geo in
            MetalCanvasView(
                zoom: zoom,
                translation: translation,
                nodes: {
                    let frame = CGRect(x: 0,
                                       y: 0,
                                       width: geo.size.width,
                                       height: geo.size.height)
                    let node = TeatroStageMetalNode(
                        id: "teatro-stage",
                        frameDoc: frame,
                        scene: scene
                    )
                    node.puppetPose = puppetPose
                    node.ballPosition = ballPosition
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
                let rig = TPPuppetRig()
                let ballScene = StageBallScene()
                var last = CACurrentMediaTime()
                while true {
                    let now = CACurrentMediaTime()
                    let dt = max(0.0, now - last)
                    last = now
                    rig.step(dt: dt, time: now)
                     ballScene.step(dt: dt)
                    let snap = rig.snapshot()
                    let pose = TeatroStageMetalNode.TeatroPuppetPose(
                        bar: TeatroVec3(x: CGFloat(snap.bar.x), y: CGFloat(snap.bar.y), z: CGFloat(snap.bar.z)),
                        torso: TeatroVec3(x: CGFloat(snap.torso.x), y: CGFloat(snap.torso.y), z: CGFloat(snap.torso.z)),
                        head: TeatroVec3(x: CGFloat(snap.head.x), y: CGFloat(snap.head.y), z: CGFloat(snap.head.z)),
                        handL: TeatroVec3(x: CGFloat(snap.handL.x), y: CGFloat(snap.handL.y), z: CGFloat(snap.handL.z)),
                        handR: TeatroVec3(x: CGFloat(snap.handR.x), y: CGFloat(snap.handR.y), z: CGFloat(snap.handR.z)),
                        footL: TeatroVec3(x: CGFloat(snap.footL.x), y: CGFloat(snap.footL.y), z: CGFloat(snap.footL.z)),
                        footR: TeatroVec3(x: CGFloat(snap.footR.x), y: CGFloat(snap.footR.y), z: CGFloat(snap.footR.z))
                    )
                    let ballSnap = ballScene.snapshot()
                    let ballVec = TeatroVec3(
                        x: CGFloat(ballSnap.position.x),
                        y: CGFloat(ballSnap.position.y),
                        z: CGFloat(ballSnap.position.z)
                    )
                    await MainActor.run {
                        puppetPose = pose
                        ballPosition = ballVec
                    }
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
            }
        }
    }
}

// MARK: - Local ball scene for visual baseline

private struct StageBallSnapshot {
    var time: Double
    var position: TPVec3
    var velocity: TPVec3
}

private final class StageBallScene {
    private let world: TPWorld
    private let ballBody: TPBody
    private var time: Double = 0
    private let radius: Double

    init(
        initialPosition: TPVec3 = TPVec3(x: 0, y: 12, z: 0),
        radius: Double = 1.0,
        mass: Double = 1.0
    ) {
        self.radius = radius
        world = TPWorld()
        world.gravity = TPVec3(x: 0, y: -9.82, z: 0)
        world.linearDamping = 0.02

        ballBody = TPBody(position: initialPosition, mass: mass)
        world.addBody(ballBody)

        world.addConstraint(StageBouncyGroundConstraint(body: ballBody, floorY: 0, radius: radius, restitution: 0.4))
    }

    func step(dt: Double) {
        guard dt > 0 else { return }
        time += dt
        world.step(dt: dt)
    }

    func snapshot() -> StageBallSnapshot {
        StageBallSnapshot(time: time, position: ballBody.position, velocity: ballBody.velocity)
    }
}

/// Simple bouncy ground contact mirroring the ball baseline: prevents
/// penetration below the floor plane and reflects vertical velocity with
/// some restitution so the ball can bounce.
private final class StageBouncyGroundConstraint: TPConstraint {
    private let body: TPBody
    private let floorY: Double
    private let radius: Double
    private let restitution: Double

    init(body: TPBody, floorY: Double = 0, radius: Double, restitution: Double = 0.4) {
        self.body = body
        self.floorY = floorY
        self.radius = radius
        self.restitution = restitution
    }

    func solve(dt: Double) {
        _ = dt
        let bottomY = body.position.y - radius
        if bottomY < floorY {
            let penetration = floorY - bottomY
            body.position.y += penetration
            if body.velocity.y < 0 {
                body.velocity.y = -body.velocity.y * restitution
            }
        }
    }
}
