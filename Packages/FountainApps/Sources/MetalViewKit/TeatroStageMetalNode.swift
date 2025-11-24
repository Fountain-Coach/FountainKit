// TeatroStageMetalNode — MetalViewKit node rendering a TeatroStageScene

#if canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import Foundation
import CoreGraphics
import QuartzCore
import Metal
import MetalKit

public final class TeatroStageMetalNode: MetalCanvasNode {
    public let id: String
    public var frameDoc: CGRect
    public var scene: TeatroStageScene
    public var puppetPose: TeatroPuppetPose?
    public var ballPosition: TeatroVec3?

    public init(id: String, frameDoc: CGRect, scene: TeatroStageScene) {
        self.id = id
        self.frameDoc = frameDoc
        self.scene = scene
    }

    public func portLayout() -> [MetalNodePort] { [] }

    public func encode(into view: MTKView,
                       device: MTLDevice,
                       encoder: MTLRenderCommandEncoder,
                       transform: MetalCanvasTransform) {
        // Paper background for the stage area
        let tl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.minY)
        let tr = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.minY)
        let bl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.maxY)
        let br = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.maxY)
        let bgVerts: [SIMD2<Float>] = [tl, bl, tr, tr, bl, br]
        encoder.setVertexBytes(bgVerts,
                               length: bgVerts.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        var bgColor = SIMD4<Float>(0.98, 0.975, 0.96, 1.0)
        encoder.setFragmentBytes(&bgColor,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: bgVerts.count)

        let center = CGPoint(x: frameDoc.midX, y: frameDoc.maxY - frameDoc.height * 0.35)

        // Draw room edges in isometric projection, mirroring the SDL demo.
        drawRoom(center: center, encoder: encoder, transform: transform)

        // Ball baseline demo (if provided).
        if let ball = ballPosition {
            drawBall(center: center, position: ball, encoder: encoder, transform: transform)
        }

        // Puppet silhouette in front of the back wall (if provided).
        if let pose = puppetPose {
            drawPuppet(center: center, pose: pose, encoder: encoder, transform: transform)
        }

        // Representatives as circles on the floor using the same projection.
        drawReps(center: center, encoder: encoder, transform: transform)

        // Simple lights: a spot on the floor and a wash on the back wall.
        drawLights(center: center, time: CACurrentMediaTime(), encoder: encoder, transform: transform)
    }

    // MARK: - Isometric helpers

    private func rotateY(_ p: TeatroVec3, azimuth: CGFloat) -> TeatroVec3 {
        let c = cos(azimuth)
        let s = sin(azimuth)
        return TeatroVec3(
            x: p.x * c - p.z * s,
            y: p.y,
            z: p.x * s + p.z * c
        )
    }

    private func isoProject(_ p: TeatroVec3, center: CGPoint) -> CGPoint {
        let scale: CGFloat = 13.0 * scene.camera.zoom
        let u = (p.x - p.z) * scale
        let v = (p.x + p.z) * scale * 0.5 - p.y * scale
        return CGPoint(x: center.x + u, y: center.y + v)
    }

    private func projectDoc(x: CGFloat,
                            y: CGFloat,
                            z: CGFloat,
                            center: CGPoint) -> CGPoint {
        let world = TeatroVec3(x: x, y: y, z: z)
        let rotated = rotateY(world, azimuth: scene.camera.azimuth)
        return isoProject(rotated, center: center)
    }

    private func drawRoom(center: CGPoint,
                          encoder: MTLRenderCommandEncoder,
                          transform: MetalCanvasTransform) {
        let floorHalfW: CGFloat = 15
        let floorHalfD: CGFloat = 10
        let h: CGFloat = 20

        func p(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SIMD2<Float> {
            let pt = projectDoc(x: x, y: y, z: z, center: center)
            return transform.docToNDC(x: pt.x, y: pt.y)
        }

        let color = SIMD4<Float>(0.07, 0.07, 0.07, 1.0)

        // Floor rectangle
        var lines: [SIMD2<Float>] = []
        let f1 = p(-floorHalfW, 0, -floorHalfD)
        let f2 = p(floorHalfW, 0, -floorHalfD)
        let f3 = p(floorHalfW, 0, floorHalfD)
        let f4 = p(-floorHalfW, 0, floorHalfD)
        lines.append(contentsOf: [f1, f2, f2, f3, f3, f4, f4, f1])

        // Back wall
        let bw1 = p(-floorHalfW, 0, -floorHalfD)
        let bw2 = p(floorHalfW, 0, -floorHalfD)
        let bw3 = p(floorHalfW, h, -floorHalfD)
        let bw4 = p(-floorHalfW, h, -floorHalfD)
        lines.append(contentsOf: [bw1, bw2, bw2, bw3, bw3, bw4, bw4, bw1])

        // Left and right walls (full rectangle outlines)
        let lwBottom = p(-floorHalfW, 0, -floorHalfD)
        let lwTop = p(-floorHalfW, h, -floorHalfD)
        let lwBottomFront = p(-floorHalfW, 0, floorHalfD)
        let lwTopFront = p(-floorHalfW, h, floorHalfD)
        // Left wall: bottom, top, and two verticals
        lines.append(contentsOf: [
            lwBottom, lwTop,           // back edge
            lwBottomFront, lwTopFront, // front edge
            lwBottom, lwBottomFront,   // floor edge
            lwTop, lwTopFront          // ceiling edge
        ])

        let rwBottom = p(floorHalfW, 0, -floorHalfD)
        let rwTop = p(floorHalfW, h, -floorHalfD)
        let rwBottomFront = p(floorHalfW, 0, floorHalfD)
        let rwTopFront = p(floorHalfW, h, floorHalfD)
        // Right wall: bottom, top, and two verticals
        lines.append(contentsOf: [
            rwBottom, rwTop,
            rwBottomFront, rwTopFront,
            rwBottom, rwBottomFront,
            rwTop, rwTopFront
        ])

        encoder.setVertexBytes(lines,
                               length: lines.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        var col = color
        encoder.setFragmentBytes(&col,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lines.count)
    }

    public struct TeatroPuppetPose: Sendable, Equatable {
        public var bar: TeatroVec3
        public var torso: TeatroVec3
        public var head: TeatroVec3
        public var handL: TeatroVec3
        public var handR: TeatroVec3
        public var footL: TeatroVec3
        public var footR: TeatroVec3
        public init(bar: TeatroVec3,
                    torso: TeatroVec3,
                    head: TeatroVec3,
                    handL: TeatroVec3,
                    handR: TeatroVec3,
                    footL: TeatroVec3,
                    footR: TeatroVec3) {
            self.bar = bar
            self.torso = torso
            self.head = head
            self.handL = handL
            self.handR = handR
            self.footL = footL
            self.footR = footR
        }
    }

    private func drawPuppet(center: CGPoint,
                            pose: TeatroPuppetPose,
                            encoder: MTLRenderCommandEncoder,
                            transform: MetalCanvasTransform) {
        func proj(_ v: TeatroVec3) -> SIMD2<Float> {
            let rotated = rotateY(v, azimuth: scene.camera.azimuth)
            let pt = isoProject(rotated, center: center)
            return transform.docToNDC(x: pt.x, y: pt.y)
        }

        // Map physics snapshot to simple puppet lines between bodies.
        let torsoTop = proj(pose.head)
        let torsoBottom = proj(pose.torso)

        var segs: [SIMD2<Float>] = [torsoTop, torsoBottom]

        let color = SIMD4<Float>(0.07, 0.07, 0.07, 1.0)

        // Arms and legs driven by physics body positions
        let armLStart = proj(pose.torso)
        let armLEnd   = proj(pose.handL)
        let armRStart = proj(pose.torso)
        let armREnd   = proj(pose.handR)
        let legLStart = proj(pose.torso)
        let legLEnd   = proj(pose.footL)
        let legRStart = proj(pose.torso)
        let legREnd   = proj(pose.footR)

        segs.append(contentsOf: [armLStart, armLEnd,
                                 armRStart, armREnd,
                                 legLStart, legLEnd,
                                 legRStart, legREnd])

        encoder.setVertexBytes(segs,
                               length: segs.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        var col = color
        encoder.setFragmentBytes(&col,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: segs.count)

        // Head as a circle of line segments
        let headRadius: CGFloat = 0.6
        let segments = 16
        var headVerts: [SIMD2<Float>] = []
        let headCenter = pose.head
        var prev = proj(TeatroVec3(x: headCenter.x + headRadius, y: headCenter.y, z: headCenter.z))
        for i in 1...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            let p = proj(TeatroVec3(
                x: headCenter.x + headRadius * cos(angle),
                y: headCenter.y,
                z: headCenter.z + headRadius * sin(angle)
            ))
            headVerts.append(contentsOf: [prev, p])
            prev = p
        }
        encoder.setVertexBytes(headVerts,
                               length: headVerts.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        encoder.setFragmentBytes(&col,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: headVerts.count)
    }

    private func drawBall(center: CGPoint,
                          position: TeatroVec3,
                          encoder: MTLRenderCommandEncoder,
                          transform: MetalCanvasTransform) {
        let radius: CGFloat = 1.0
        let color = SIMD4<Float>(0.07, 0.07, 0.07, 1.0)
        let base = TeatroVec3(x: position.x, y: position.y, z: position.z)
        var verts: [SIMD2<Float>] = []
        let segments = 24
        var prevPoint = isoProject(rotateY(TeatroVec3(x: base.x + radius, y: base.y, z: base.z),
                                           azimuth: scene.camera.azimuth),
                                   center: center)
        for i in 1...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            let world = TeatroVec3(
                x: base.x + radius * cos(angle),
                y: base.y,
                z: base.z + radius * sin(angle)
            )
            let pt = isoProject(rotateY(world, azimuth: scene.camera.azimuth), center: center)
            let v0 = transform.docToNDC(x: prevPoint.x, y: prevPoint.y)
            let v1 = transform.docToNDC(x: pt.x, y: pt.y)
            verts.append(contentsOf: [v0, v1])
            prevPoint = pt
        }
        encoder.setVertexBytes(verts,
                               length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        var col = color
        encoder.setFragmentBytes(&col,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: verts.count)
    }

    private func drawReps(center: CGPoint,
                          encoder: MTLRenderCommandEncoder,
                          transform: MetalCanvasTransform) {
        guard !scene.reps.isEmpty else { return }
        let radius: CGFloat = 0.6
        let color = SIMD4<Float>(0.07, 0.07, 0.07, 1.0)
        for rep in scene.reps {
            let base = TeatroVec3(x: rep.position.x, y: 0.02, z: rep.position.z)
            var verts: [SIMD2<Float>] = []
            let segments = 12
            var prevPoint = isoProject(rotateY(TeatroVec3(x: base.x + radius, y: base.y, z: base.z),
                                               azimuth: scene.camera.azimuth),
                                       center: center)
            for i in 1...segments {
                let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
                let world = TeatroVec3(
                    x: base.x + radius * cos(angle),
                    y: base.y,
                    z: base.z + radius * sin(angle)
                )
                let pt = isoProject(rotateY(world, azimuth: scene.camera.azimuth), center: center)
                let v0 = transform.docToNDC(x: prevPoint.x, y: prevPoint.y)
                let v1 = transform.docToNDC(x: pt.x, y: pt.y)
                verts.append(contentsOf: [v0, v1])
                prevPoint = pt
            }
            encoder.setVertexBytes(verts,
                                   length: verts.count * MemoryLayout<SIMD2<Float>>.stride,
                                   index: 0)
            var col = color
            encoder.setFragmentBytes(&col,
                                     length: MemoryLayout<SIMD4<Float>>.size,
                                     index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: verts.count)
        }
    }

    private func drawLights(center: CGPoint,
                            time: TimeInterval,
                            encoder: MTLRenderCommandEncoder,
                            transform: MetalCanvasTransform) {
        func proj(_ v: TeatroVec3) -> SIMD2<Float> {
            let rotated = rotateY(v, azimuth: scene.camera.azimuth)
            let pt = isoProject(rotated, center: center)
            return transform.docToNDC(x: pt.x, y: pt.y)
        }

        let t = CGFloat(time)

        // Floor spot at origin, pulsing slightly.
        let baseRadius: CGFloat = 4
        let pulse = 1.0 + 0.1 * sin(t * 1.2)
        let spotRadius = baseRadius * pulse
        let spotSegments = 32
        let spotColor = SIMD4<Float>(0.98, 0.94, 0.85, 1.0)
        var spotVerts: [SIMD2<Float>] = []
        let ringCount = 3
        for ring in 0..<ringCount {
            let r = spotRadius * (1.0 - CGFloat(ring) * 0.2)
            var prev = proj(TeatroVec3(x: r, y: 0.01, z: 0))
            for i in 1...spotSegments {
                let angle = (CGFloat(i) / CGFloat(spotSegments)) * 2 * .pi
                let p = proj(TeatroVec3(x: r * cos(angle), y: 0.01, z: r * sin(angle)))
                spotVerts.append(contentsOf: [prev, p])
                prev = p
            }
        }
        encoder.setVertexBytes(spotVerts,
                               length: spotVerts.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        var spotCol = spotColor
        encoder.setFragmentBytes(&spotCol,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: spotVerts.count)

        // Back wall wash rectangle.
        let washHalfW: CGFloat = 6
        let washHalfH: CGFloat = 4
        let zBack: CGFloat = -10
        let yCenter: CGFloat = 8
        let w1 = proj(TeatroVec3(x: -washHalfW, y: yCenter - washHalfH, z: zBack + 0.01))
        let w2 = proj(TeatroVec3(x: washHalfW, y: yCenter - washHalfH, z: zBack + 0.01))
        let w3 = proj(TeatroVec3(x: washHalfW, y: yCenter + washHalfH, z: zBack + 0.01))
        let w4 = proj(TeatroVec3(x: -washHalfW, y: yCenter + washHalfH, z: zBack + 0.01))
        let washColor = SIMD4<Float>(0.97, 0.93, 0.85, 1.0)
        let washVerts: [SIMD2<Float>] = [w1, w2, w2, w3, w3, w4, w4, w1]
        encoder.setVertexBytes(washVerts,
                               length: washVerts.count * MemoryLayout<SIMD2<Float>>.stride,
                               index: 0)
        var washCol = washColor
        encoder.setFragmentBytes(&washCol,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: washVerts.count)
    }

    // Legacy helpers removed: circles and ellipses are now handled via the isometric drawing paths above.
}

#endif
