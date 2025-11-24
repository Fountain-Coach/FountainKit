import Foundation
import SDLKit
#if canImport(CSDL3)
import CSDL3
#endif

private struct Vec3 {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
}

private struct CameraState {
    var azimuth: CGFloat   // rotation around Y
    var zoom: CGFloat
}

private struct Rep {
    var position: Vec3
}

private struct Snapshot {
    var time: CGFloat
    var camera: CameraState
    var repPositions: [Vec3]
}

@main
@MainActor
struct TeatroEngineDemoApp {
    static func main() {
        do {
            let width = 1440
            let height = 900
            let window = SDLWindow(config: .init(title: "Teatro Engine Demo", width: width, height: height))
            try window.open()
            try window.show()
            let renderer = try SDLRenderer(width: width, height: height, window: window)

            var running = true
            var camera = CameraState(azimuth: .pi / 4, zoom: 1.0)

            var reps: [Rep] = [
                Rep(position: Vec3(x: 0, y: 0, z: 0)),
                Rep(position: Vec3(x: -5, y: 0, z: 3))
            ]

            var history: [Snapshot] = []
            let maxHistoryFrames = 600

            #if canImport(CSDL3)
            var dragging = false
            var lastX: CGFloat = 0
            var isZooming = false
            var zoomStartY: CGFloat = 0
            var draggingRepIndex: Int? = nil
            var scrubbing = false
            var scrubT: CGFloat = 1.0
            #endif

            let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.65)

            let fps: Double = 60
            let frameTime: useconds_t = useconds_t(1_000_000.0 / fps)
            var time: CGFloat = 0

            while running {
                #if canImport(CSDL3)
                var event = SDLKit_Event(type: 0, x: 0, y: 0, keycode: 0, button: 0)
                while SDLKit_PollEvent(&event) != 0 {
                    let type = Int32(bitPattern: event.type)
                    switch type {
                    case Int32(SDLKIT_EVENT_QUIT),
                         Int32(SDLKIT_EVENT_WINDOW_CLOSED):
                        running = false
                    case Int32(SDLKIT_EVENT_MOUSE_DOWN):
                        let pos = CGPoint(x: CGFloat(event.x), y: CGFloat(event.y))
                        if event.button == 1 {
                            // Timeline region: band above the bottom (so it is never hidden by the OS)
                            if pos.y >= CGFloat(height) - 120 {
                                scrubbing = true
                                scrubT = scrubPositionToT(x: pos.x, width: width)
                            } else {
                                // Try to grab a representative on the floor first; fall back to camera orbit
                                let world = viewToFloor(point: pos, camera: camera, center: center)
                                if let hit = hitRep(at: world, reps: reps) {
                                    draggingRepIndex = hit
                                } else {
                                    dragging = true
                                    lastX = pos.x
                                }
                            }
                        } else if event.button == 3 {
                            isZooming = true
                            zoomStartY = pos.y
                        }
                    case Int32(SDLKIT_EVENT_MOUSE_UP):
                        if event.button == 1 {
                            dragging = false
                            draggingRepIndex = nil
                            scrubbing = false
                        } else if event.button == 3 {
                            isZooming = false
                        }
                    case Int32(SDLKIT_EVENT_MOUSE_MOVE):
                        let x = CGFloat(event.x)
                        let y = CGFloat(event.y)
                        if scrubbing {
                            let pos = CGPoint(x: x, y: y)
                            scrubT = scrubPositionToT(x: pos.x, width: width)
                        } else if let idx = draggingRepIndex {
                            let pos = CGPoint(x: x, y: y)
                            let world = viewToFloor(point: pos, camera: camera, center: center)
                            reps[idx].position = world
                        } else if dragging {
                            let dx = x - lastX
                            lastX = x
                            camera.azimuth += dx * 0.003
                        } else if isZooming {
                            let dy = y - zoomStartY
                            let factor: CGFloat = 1.0 - dy * 0.002
                            camera.zoom = max(0.5, min(3.0, camera.zoom * factor))
                            zoomStartY = y
                        }
                    default:
                        break
                    }
                }
                #endif

                // Advance live time and record into history when not scrubbing
                try renderer.clear(color: 0xFFF4EAD6)

                if !scrubbing {
                    time += CGFloat(1.0 / fps)
                    history.append(Snapshot(time: time, camera: camera, repPositions: reps.map { $0.position }))
                    if history.count > maxHistoryFrames {
                        history.removeFirst(history.count - maxHistoryFrames)
                    }
                }

                let renderState: (time: CGFloat, camera: CameraState, reps: [Rep])
                if scrubbing, let snap = snapshotForT(scrubT, history: history) {
                    let rsReps = snap.repPositions.map { Rep(position: $0) }
                    renderState = (snap.time, snap.camera, rsReps)
                } else {
                    renderState = (time, camera, reps)
                }

                drawRoom(renderer: renderer, camera: renderState.camera, center: center)
                drawPuppetSilhouette(renderer: renderer, camera: renderState.camera, center: center, time: renderState.time)
                drawReps(renderer: renderer, camera: renderState.camera, center: center, reps: renderState.reps)
                drawLights(renderer: renderer, camera: renderState.camera, center: center, time: renderState.time)
                drawTimeline(renderer: renderer, width: width, height: height, historyCount: history.count, scrubT: scrubT, scrubbing: scrubbing)

                renderer.present()
                usleep(frameTime)
            }

            renderer.shutdown()
            window.close()
        } catch {
            fputs("teatro-engine-demo failed: \(error)\n", stderr)
        }
    }

    private static func rotateY(_ p: Vec3, azimuth: CGFloat) -> Vec3 {
        let c = cos(azimuth)
        let s = sin(azimuth)
        return Vec3(
            x: p.x * c - p.z * s,
            y: p.y,
            z: p.x * s + p.z * c
        )
    }

    private static func isoProject(_ p: Vec3, camera: CameraState, center: CGPoint) -> CGPoint {
        // Simple isometric-style projection: world (x,z) → skewed 2D, y lifts downward.
        // Scale tuned to make the stage occupy a generous portion of the window.
        let scale: CGFloat = 13.0 * camera.zoom
        let u = (p.x - p.z) * scale
        let v = (p.x + p.z) * scale * 0.5 - p.y * scale
        return CGPoint(x: center.x + u, y: center.y + v)
    }

    private static func viewToFloor(point: CGPoint, camera: CameraState, center: CGPoint) -> Vec3 {
        // Invert the simple isometric projection for points on the floor plane (y = 0).
        let scale: CGFloat = 13.0 * camera.zoom
        let u = (point.x - center.x) / scale
        let v = (point.y - center.y) / scale
        let a = u
        let b = v
        let xr = (a + 2 * b) / 2
        let zr = (2 * b - a) / 2
        // Rotate back around Y by -azimuth to get world coordinates.
        let c = cos(-camera.azimuth)
        let s = sin(-camera.azimuth)
        let x = xr * c - zr * s
        let z = xr * s + zr * c
        return Vec3(x: x, y: 0, z: z)
    }

    private static func hitRep(at world: Vec3, reps: [Rep]) -> Int? {
        var bestIndex: Int?
        var bestDist2 = CGFloat.greatestFiniteMagnitude
        for (i, rep) in reps.enumerated() {
            let dx = world.x - rep.position.x
            let dz = world.z - rep.position.z
            let d2 = dx*dx + dz*dz
            if d2 < bestDist2 && d2 <= 2.0 * 2.0 { // radius ~2
                bestDist2 = d2
                bestIndex = i
            }
        }
        return bestIndex
    }

    private static func scrubPositionToT(x: CGFloat, width: Int) -> CGFloat {
        let w = CGFloat(width)
        let margin: CGFloat = w * 0.15
        let x0 = margin
        let x1 = w - margin
        if x1 <= x0 { return 1.0 }
        let clamped = min(max(x, x0), x1)
        return (clamped - x0) / (x1 - x0)
    }

    private static func snapshotForT(_ t: CGFloat, history: [Snapshot]) -> Snapshot? {
        guard !history.isEmpty else { return nil }
        let clamped = min(max(t, 0), 1)
        let idx = Int((clamped * CGFloat(history.count - 1)).rounded())
        return history[idx]
    }

    private static func drawRoom(renderer: SDLRenderer, camera: CameraState, center: CGPoint) {
        // Room dimensions similar to demo1: floor 30x20, walls up to height 20
        let floorHalfW: CGFloat = 15
        let floorHalfD: CGFloat = 10
        let h: CGFloat = 20

        func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            let world = Vec3(x: x, y: y, z: z)
            let rotated = rotateY(world, azimuth: camera.azimuth)
            return isoProject(rotated, camera: camera, center: center)
        }

        // Floor rectangle
        let f1 = project(-floorHalfW, 0, -floorHalfD)
        let f2 = project(floorHalfW, 0, -floorHalfD)
        let f3 = project(floorHalfW, 0, floorHalfD)
        let f4 = project(-floorHalfW, 0, floorHalfD)
        let color: UInt32 = 0xFF111111
        try? renderer.drawLine(x1: Int(f1.x), y1: Int(f1.y), x2: Int(f2.x), y2: Int(f2.y), color: color)
        try? renderer.drawLine(x1: Int(f2.x), y1: Int(f2.y), x2: Int(f3.x), y2: Int(f3.y), color: color)
        try? renderer.drawLine(x1: Int(f3.x), y1: Int(f3.y), x2: Int(f4.x), y2: Int(f4.y), color: color)
        try? renderer.drawLine(x1: Int(f4.x), y1: Int(f4.y), x2: Int(f1.x), y2: Int(f1.y), color: color)

        // Back wall
        let bw1 = project(-floorHalfW, 0, -floorHalfD)
        let bw2 = project(floorHalfW, 0, -floorHalfD)
        let bw3 = project(floorHalfW, h, -floorHalfD)
        let bw4 = project(-floorHalfW, h, -floorHalfD)
        try? renderer.drawLine(x1: Int(bw1.x), y1: Int(bw1.y), x2: Int(bw2.x), y2: Int(bw2.y), color: color)
        try? renderer.drawLine(x1: Int(bw2.x), y1: Int(bw2.y), x2: Int(bw3.x), y2: Int(bw3.y), color: color)
        try? renderer.drawLine(x1: Int(bw3.x), y1: Int(bw3.y), x2: Int(bw4.x), y2: Int(bw4.y), color: color)
        try? renderer.drawLine(x1: Int(bw4.x), y1: Int(bw4.y), x2: Int(bw1.x), y2: Int(bw1.y), color: color)

        // Left and right walls (edges only)
        let lwBottom = project(-floorHalfW, 0, -floorHalfD)
        let lwTop = project(-floorHalfW, h, -floorHalfD)
        let lwBottomFront = project(-floorHalfW, 0, floorHalfD)
        let lwTopFront = project(-floorHalfW, h, floorHalfD)
        try? renderer.drawLine(x1: Int(lwBottom.x), y1: Int(lwBottom.y), x2: Int(lwTop.x), y2: Int(lwTop.y), color: color)
        try? renderer.drawLine(x1: Int(lwBottomFront.x), y1: Int(lwBottomFront.y), x2: Int(lwTopFront.x), y2: Int(lwTopFront.y), color: color)

        let rwBottom = project(floorHalfW, 0, -floorHalfD)
        let rwTop = project(floorHalfW, h, -floorHalfD)
        let rwBottomFront = project(floorHalfW, 0, floorHalfD)
        let rwTopFront = project(floorHalfW, h, floorHalfD)
        try? renderer.drawLine(x1: Int(rwBottom.x), y1: Int(rwBottom.y), x2: Int(rwTop.x), y2: Int(rwTop.y), color: color)
        try? renderer.drawLine(x1: Int(rwBottomFront.x), y1: Int(rwBottomFront.y), x2: Int(rwTopFront.x), y2: Int(rwTopFront.y), color: color)
    }

    private static func drawPuppetSilhouette(renderer: SDLRenderer, camera: CameraState, center: CGPoint, time: CGFloat) {
        // Minimal static puppet: torso, head, simple arms/legs in front of back wall
        func project(_ v: Vec3) -> CGPoint {
            let rotated = rotateY(v, azimuth: camera.azimuth)
            return isoProject(rotated, camera: camera, center: center)
        }

        let swayX = sin(time * 0.7) * 0.4
        let bobY = sin(time * 1.1) * 0.3

        let torsoTopWorld = Vec3(x: swayX, y: 9 + bobY, z: 0)
        let torsoBottomWorld = Vec3(x: swayX, y: 6 + bobY, z: 0)
        let torsoTop = project(torsoTopWorld)
        let torsoBottom = project(torsoBottomWorld)
        let color: UInt32 = 0xFF111111
        try? renderer.drawLine(x1: Int(torsoTop.x), y1: Int(torsoTop.y), x2: Int(torsoBottom.x), y2: Int(torsoBottom.y), color: color)

        let headRadius: CGFloat = 0.6
        let segments = 16
        var prev = project(Vec3(x: swayX + headRadius, y: 11 + bobY, z: 0))
        for i in 1...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            let p = project(Vec3(x: swayX + headRadius * cos(angle), y: 11 + bobY, z: headRadius * sin(angle)))
            try? renderer.drawLine(x1: Int(prev.x), y1: Int(prev.y), x2: Int(p.x), y2: Int(p.y), color: color)
            prev = p
        }

        // Simple arms and legs
        let armSwing = sin(time * 1.3) * 0.8
        let legSwing = sin(time * 1.3 + .pi / 2) * 0.6
        let armLStart = project(Vec3(x: swayX - 0.8, y: 8.2 + bobY, z: 0))
        let armLEnd   = project(Vec3(x: swayX - 2.0, y: 7.0 + bobY + armSwing * 0.3, z: 0))
        let armRStart = project(Vec3(x: swayX + 0.8, y: 8.2 + bobY, z: 0))
        let armREnd   = project(Vec3(x: swayX + 2.0, y: 7.0 + bobY - armSwing * 0.3, z: 0))
        let legLStart = torsoBottom
        let legLEnd   = project(Vec3(x: swayX - 0.6, y: 4.0 + bobY + legSwing * 0.3, z: 0))
        let legRStart = torsoBottom
        let legREnd   = project(Vec3(x: swayX + 0.6, y: 4.0 + bobY - legSwing * 0.3, z: 0))
        try? renderer.drawLine(x1: Int(armLStart.x), y1: Int(armLStart.y), x2: Int(armLEnd.x), y2: Int(armLEnd.y), color: color)
        try? renderer.drawLine(x1: Int(armRStart.x), y1: Int(armRStart.y), x2: Int(armREnd.x), y2: Int(armREnd.y), color: color)
        try? renderer.drawLine(x1: Int(legLStart.x), y1: Int(legLStart.y), x2: Int(legLEnd.x), y2: Int(legLEnd.y), color: color)
        try? renderer.drawLine(x1: Int(legRStart.x), y1: Int(legRStart.y), x2: Int(legREnd.x), y2: Int(legREnd.y), color: color)

        // Backlight hint around head: a slightly lighter circle, a bit larger
        let backlightColor: UInt32 = 0xFFF9F0E0
        prev = project(Vec3(x: swayX + headRadius * 1.3, y: 11 + bobY, z: 0))
        for i in 1...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            let p = project(Vec3(x: swayX + headRadius * 1.3 * cos(angle), y: 11 + bobY, z: headRadius * 1.3 * sin(angle)))
            try? renderer.drawLine(x1: Int(prev.x), y1: Int(prev.y), x2: Int(p.x), y2: Int(p.y), color: backlightColor)
            prev = p
        }
    }

    private static func drawLights(renderer: SDLRenderer, camera: CameraState, center: CGPoint, time: CGFloat) {
        func project(_ v: Vec3) -> CGPoint {
            let rotated = rotateY(v, azimuth: camera.azimuth)
            return isoProject(rotated, camera: camera, center: center)
        }

        // Spot on the floor at puppet's feet (0,0,0) approximated as multiple rings
        let baseRadius: CGFloat = 4
        let pulse = 1.0 + 0.1 * sin(time * 1.2)
        let spotRadius = baseRadius * pulse
        let spotSegments = 32
        let spotColor: UInt32 = 0xFFF9F0E0
        let ringCount = 3
        for ring in 0..<ringCount {
            let r = spotRadius * (1.0 - CGFloat(ring) * 0.2)
            var prev = project(Vec3(x: r, y: 0.01, z: 0))
            for i in 1...spotSegments {
                let angle = (CGFloat(i) / CGFloat(spotSegments)) * 2 * .pi
                let p = project(Vec3(x: r * cos(angle), y: 0.01, z: r * sin(angle)))
                try? renderer.drawLine(x1: Int(prev.x), y1: Int(prev.y), x2: Int(p.x), y2: Int(p.y), color: spotColor)
                prev = p
            }
        }

        // Wash on the back wall: simple rectangle outline
        let washHalfW: CGFloat = 6
        let washHalfH: CGFloat = 4
        let zBack: CGFloat = -10
        let yCenter: CGFloat = 8
        let w1 = project(Vec3(x: -washHalfW, y: yCenter - washHalfH, z: zBack + 0.01))
        let w2 = project(Vec3(x: washHalfW, y: yCenter - washHalfH, z: zBack + 0.01))
        let w3 = project(Vec3(x: washHalfW, y: yCenter + washHalfH, z: zBack + 0.01))
        let w4 = project(Vec3(x: -washHalfW, y: yCenter + washHalfH, z: zBack + 0.01))
        let washColor: UInt32 = 0xFFF7EFE0
        try? renderer.drawLine(x1: Int(w1.x), y1: Int(w1.y), x2: Int(w2.x), y2: Int(w2.y), color: washColor)
        try? renderer.drawLine(x1: Int(w2.x), y1: Int(w2.y), x2: Int(w3.x), y2: Int(w3.y), color: washColor)
        try? renderer.drawLine(x1: Int(w3.x), y1: Int(w3.y), x2: Int(w4.x), y2: Int(w4.y), color: washColor)
        try? renderer.drawLine(x1: Int(w4.x), y1: Int(w4.y), x2: Int(w1.x), y2: Int(w1.y), color: washColor)
    }

    private static func drawReps(renderer: SDLRenderer, camera: CameraState, center: CGPoint, reps: [Rep]) {
        func project(_ v: Vec3) -> CGPoint {
            let rotated = rotateY(v, azimuth: camera.azimuth)
            return isoProject(rotated, camera: camera, center: center)
        }
        let color: UInt32 = 0xFF111111
        let radius: CGFloat = 0.6
        let segments = 12
        for rep in reps {
            var prev = project(Vec3(x: rep.position.x + radius, y: 0.02, z: rep.position.z))
            for i in 1...segments {
                let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
                let p = project(Vec3(x: rep.position.x + radius * cos(angle), y: 0.02, z: rep.position.z + radius * sin(angle)))
                try? renderer.drawLine(x1: Int(prev.x), y1: Int(prev.y), x2: Int(p.x), y2: Int(p.y), color: color)
                prev = p
            }
        }
    }

    private static func drawTimeline(renderer: SDLRenderer, width: Int, height: Int, historyCount: Int, scrubT: CGFloat, scrubbing: Bool) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let marginX: CGFloat = w * 0.15
        let x0 = marginX
        let x1 = w - marginX
        // Place the bar well above the bottom edge so it is not obscured by the OS chrome.
        let y = h - 90
        let baseColor: UInt32 = 0xFF8C7E64   // darker than background
        let markerColor: UInt32 = 0xFF111111

        // Draw a slightly thicker base line (3 px tall) so it is clearly visible.
        for offset in -1...1 {
            try? renderer.drawLine(x1: Int(x0), y1: Int(y) + offset, x2: Int(x1), y2: Int(y) + offset, color: baseColor)
        }

        guard historyCount > 0 else { return }

        // Marker at latest frame when not scrubbing, otherwise at scrubT
        let t = scrubbing ? scrubT : 1.0
        let mx = x0 + (x1 - x0) * min(max(t, 0), 1)
        try? renderer.drawLine(x1: Int(mx), y1: Int(y - 8), x2: Int(mx), y2: Int(y + 8), color: markerColor)
    }
}
