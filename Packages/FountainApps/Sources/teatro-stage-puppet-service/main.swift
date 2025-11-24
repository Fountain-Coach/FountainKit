import Foundation
import FountainRuntime
import LauncherSignature
import TeatroPhysics

/// Teatro Stage Puppet instrument service.
/// Thin HTTP wrapper around `TPPuppetRig` implementing `teatro-stage-puppet.yml`.
@main
enum TeatroStagePuppetServiceMain {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" {
            verifyLauncherSignature()
        }

        let kernel = HTTPKernel { req in
            await handle(request: req)
        }
        let server = NIOHTTPServer(kernel: kernel)

        do {
            let portEnv = env["TEATRO_STAGE_PUPPET_PORT"] ?? env["PORT"] ?? "8093"
            let port = Int(portEnv) ?? 8093
            _ = try await server.start(port: port)
            print("teatro-stage-puppet-service listening on :\(port)")
        } catch {
            let msg = "[teatro-stage-puppet] failed to start: \(error)\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(2)
        }

        dispatchMain()
    }

    /// Single long-lived puppet engine instance.
    private static let engine = PuppetEngine()

    private static func handle(request: HTTPRequest) async -> HTTPResponse {
        // Serve curated OpenAPI spec.
        if request.method == "GET", request.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainSpecCuration/openapi/v1/teatro-stage-puppet.yml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
            return HTTPResponse(status: 404)
        }

        // Simple liveness metric.
        if request.method == "GET", request.path == "/metrics" {
            let body = Data("teatro_stage_puppet_up 1\n".utf8)
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
        }

        switch (request.method, request.path) {
        case ("GET", "/puppet/pose"):
            return await handleGetPose()
        case ("POST", "/puppet/reset"):
            return await handleReset()
        case ("GET", "/puppet/gestures"):
            return handleListGestures()
        case ("POST", "/puppet/gestures/play"):
            return await handlePlayGesture(request: request)
        case ("GET", "/puppet/health"):
            return await handleGetHealth()
        default:
            return HTTPResponse(status: 404)
        }
    }

    private static func handleGetPose() async -> HTTPResponse {
        // Advance by a small fixed timestep to keep the puppet lively when polled.
        let dt = 1.0 / 60.0
        let (time, snap) = await engine.snapshot(stepBy: dt)

        func encodeBody(id: String, vec: TPVec3) -> [String: Any] {
            [
                "id": id,
                "position": [
                    "x": vec.x,
                    "y": vec.y,
                    "z": vec.z
                ]
            ]
        }

        let bodies: [[String: Any]] = [
            encodeBody(id: "controller", vec: snap.controller),
            encodeBody(id: "bar", vec: snap.bar),
            encodeBody(id: "torso", vec: snap.torso),
            encodeBody(id: "head", vec: snap.head),
            encodeBody(id: "handL", vec: snap.handL),
            encodeBody(id: "handR", vec: snap.handR),
            encodeBody(id: "footL", vec: snap.footL),
            encodeBody(id: "footR", vec: snap.footR)
        ]

        let obj: [String: Any] = [
            "time": time,
            "bodies": bodies
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return HTTPResponse(
            status: 200,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    private static func handleReset() async -> HTTPResponse {
        await engine.reset()
        return HTTPResponse(status: 204)
    }

    private static func handleListGestures() -> HTTPResponse {
        // Initial static gesture catalogue. The engine can map these ids to
        // concrete motion patterns internally.
        let gestures: [[String: Any]] = [
            [
                "id": "idle-sway",
                "name": "Idle sway",
                "description": "Subtle continuous sway of the puppet under gravity.",
                "typicalDuration": 5.0
            ],
            [
                "id": "bow",
                "name": "Bow",
                "description": "Short bow towards the audience.",
                "typicalDuration": 2.0
            ],
            [
                "id": "wave",
                "name": "Wave",
                "description": "One-handed wave gesture.",
                "typicalDuration": 2.0
            ]
        ]
        let obj: [String: Any] = ["gestures": gestures]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return HTTPResponse(
            status: 200,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    private static func handlePlayGesture(request: HTTPRequest) async -> HTTPResponse {
        guard
            let obj = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
            let gestureId = obj["gestureId"] as? String,
            !gestureId.isEmpty
        else {
            return error(status: 400, reason: "invalid gesture request")
        }

        let startedAt = await engine.markGestureStarted(id: gestureId)

        let payload: [String: Any] = [
            "gestureId": gestureId,
            "startedAt": startedAt
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return HTTPResponse(
            status: 202,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    private static func handleGetHealth() async -> HTTPResponse {
        let health = await engine.health()
        let obj: [String: Any] = [
            "ok": health.ok,
            "feetOnStage": health.feetOnStage,
            "withinStageBounds": health.withinStageBounds,
            "stringsStable": health.stringsStable,
            "notes": health.notes
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return HTTPResponse(
            status: 200,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    private static func error(status: Int, reason: String) -> HTTPResponse {
        let obj: [String: Any] = ["code": "\(status)", "message": reason]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }
}

// MARK: - Puppet engine actor

actor PuppetEngine {
    private var rig: TPPuppetRig
    private var time: Double

    private let restSnapshot: TPPuppetSnapshot
    private let restControllerBar: Double
    private let restControllerHandL: Double
    private let restControllerHandR: Double
    private let restBarHead: Double

    private var lastGestureId: String?

    init() {
        let rig = TPPuppetRig()
        let snap = rig.snapshot()

        func length(_ a: TPVec3, _ b: TPVec3) -> Double {
            (b - a).length()
        }

        self.rig = rig
        self.time = 0
        self.restSnapshot = snap
        self.restControllerBar = length(snap.controller, snap.bar)
        self.restControllerHandL = length(snap.controller, snap.handL)
        self.restControllerHandR = length(snap.controller, snap.handR)
        self.restBarHead = length(snap.bar, snap.head)
    }

    func reset() {
        let rig = TPPuppetRig()
        self.rig = rig
        self.time = 0
        // Keep rest lengths from the original rig; they match the spec coordinates.
    }

    func snapshot(stepBy dt: Double) -> (Double, TPPuppetSnapshot) {
        if dt > 0 {
            time += dt
            rig.step(dt: dt, time: time)
        }
        return (time, rig.snapshot())
    }

    func markGestureStarted(id: String) -> Double {
        lastGestureId = id
        // For now gestures do not modify the rig; we just mark the start time.
        return time
    }

    struct Health {
        var ok: Bool
        var feetOnStage: Bool
        var withinStageBounds: Bool
        var stringsStable: Bool
        var notes: [String]
    }

    func health() -> Health {
        let snap = rig.snapshot()
        var notes: [String] = []

        // Feet near the floor plane.
        let feetOnStage = snap.footL.y >= -0.05 && snap.footR.y >= -0.05
        if !feetOnStage {
            notes.append("feetOffStage")
        }

        // Keep torso and head within a generous horizontal and vertical corridor.
        let torsoInBounds = abs(snap.torso.x) <= 5.0 && snap.torso.y >= 0.0 && snap.torso.y <= 20.0
        let headInBounds = abs(snap.head.x) <= 5.0 && snap.head.y >= 0.0 && snap.head.y <= 25.0
        let withinStageBounds = torsoInBounds && headInBounds
        if !withinStageBounds {
            notes.append("bodyOutOfBounds")
        }

        func length(_ a: TPVec3, _ b: TPVec3) -> Double {
            (b - a).length()
        }

        let currentControllerBar = length(snap.controller, snap.bar)
        let currentControllerHandL = length(snap.controller, snap.handL)
        let currentControllerHandR = length(snap.controller, snap.handR)
        let currentBarHead = length(snap.bar, snap.head)

        func inStretchBand(current: Double, rest: Double) -> Bool {
            current >= 0.8 * rest && current <= 1.2 * rest && current >= 0.5 * rest
        }

        let stringsStable =
            inStretchBand(current: currentControllerBar, rest: restControllerBar) &&
            inStretchBand(current: currentControllerHandL, rest: restControllerHandL) &&
            inStretchBand(current: currentControllerHandR, rest: restControllerHandR) &&
            inStretchBand(current: currentBarHead, rest: restBarHead)

        if !stringsStable {
            notes.append("stringsOutOfRange")
        }

        let ok = feetOnStage && withinStageBounds && stringsStable
        return Health(ok: ok,
                      feetOnStage: feetOnStage,
                      withinStageBounds: withinStageBounds,
                      stringsStable: stringsStable,
                      notes: notes)
    }
}

