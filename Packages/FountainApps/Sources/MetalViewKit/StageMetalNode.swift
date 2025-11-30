// StageMetalNode — node = page (doc-space) with baseline-aligned ports

#if canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import Foundation
import CoreGraphics
import Metal
import MetalKit

public struct MVKMargins: Sendable, Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.init(top: top, left: leading, bottom: bottom, right: trailing)
    }
}

public final class StageMetalNode: MetalCanvasNode {
    public let id: String
    public var frameDoc: CGRect
    public var title: String
    public var page: String // "A4" or "Letter"
    public var margins: MVKMargins
    public var baseline: CGFloat
    public init(id: String, frameDoc: CGRect, title: String, page: String, margins: MVKMargins, baseline: CGFloat) {
        self.id = id; self.frameDoc = frameDoc; self.title = title; self.page = page; self.margins = margins; self.baseline = baseline
    }
    public func portLayout() -> [MetalNodePort] {
        let count = StageMetalNode.baselineCount(page: page, margins: margins, baseline: baseline)
        guard count > 0 else { return [] }
        var ports: [MetalNodePort] = []
        // Place ports at baseline midpoints along the left margin
        let innerTop = margins.top
        let step = max(1, baseline)
        // Midpoints between baseline lines => offset 0.5*step from the start
        for i in 0..<count {
            let y = innerTop + (CGFloat(i) + 0.5) * step
            ports.append(.init(id: "in\(i)", side: .left, dir: .input, centerLocal: CGPoint(x: margins.left, y: y)))
        }
        return ports
    }
    public func portDocCenters() -> [MetalNodePortCenter] {
        // Compute doc-space centers by scaling canonical page-local centers
        let pg = StageMetalNode.pageSize(page)
        let sx = frameDoc.width / max(1, pg.width)
        let sy = frameDoc.height / max(1, pg.height)
        let count = StageMetalNode.baselineCount(page: page, margins: margins, baseline: baseline)
        guard count > 0 else { return [] }
        var out: [MetalNodePortCenter] = []
        for (i, p) in portLayout().enumerated() {
            let dx = p.centerLocal.x * sx
            let dy = p.centerLocal.y * sy
            let doc = CGPoint(x: frameDoc.minX + dx, y: frameDoc.minY + dy)
            out.append(.init(id: "in\(i)", dir: .input, side: .left, doc: doc))
        }
        return out
    }
    public func encode(into view: MTKView, device: MTLDevice, encoder: MTLRenderCommandEncoder, transform: MetalCanvasTransform) {
        // Compute scale from canonical page size to current frame
        let pg = StageMetalNode.pageSize(page)
        let sx = frameDoc.width / max(1, pg.width)
        let sy = frameDoc.height / max(1, pg.height)
        let left = margins.left * sx
        let right = margins.right * sx
        let top = margins.top * sy
        let bottom = margins.bottom * sy
        let inner = CGRect(x: frameDoc.minX + left,
                           y: frameDoc.minY + top,
                           width: max(0, frameDoc.width - left - right),
                           height: max(0, frameDoc.height - top - bottom))
        // 1) Page fill (white)
        var fillVerts: [SIMD2<Float>] = []
        let tl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.minY)
        let tr = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.minY)
        let bl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.maxY)
        let br = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.maxY)
        fillVerts.append(contentsOf: [tl, bl, tr, tr, bl, br])
        encoder.setVertexBytes(fillVerts, length: fillVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var colorFill = SIMD4<Float>(1,1,1,1) // white page
        encoder.setFragmentBytes(&colorFill, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        // 2) Margin guides (light gray rectangle)
        var guideVerts: [SIMD2<Float>] = []
        let gtl = transform.docToNDC(x: inner.minX, y: inner.minY)
        let gtr = transform.docToNDC(x: inner.maxX, y: inner.minY)
        let gbl = transform.docToNDC(x: inner.minX, y: inner.maxY)
        let gbr = transform.docToNDC(x: inner.maxX, y: inner.maxY)
        guideVerts.append(contentsOf: [gtl, gtr, gtr, gbr, gbr, gbl, gbl, gtl])
        encoder.setVertexBytes(guideVerts, length: guideVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var colorGuide = SIMD4<Float>(0.85,0.85,0.88,1)
        encoder.setFragmentBytes(&colorGuide, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: guideVerts.count)
        // 3) Baseline grid (fine lines)
        let count = StageMetalNode.baselineCount(page: page, margins: margins, baseline: baseline)
        if count > 0 {
            let step = baseline * sy
            var y = inner.minY + step // first baseline line
            var baselineVerts: [SIMD2<Float>] = []
            for _ in 0..<count {
                let l = transform.docToNDC(x: inner.minX, y: y)
                let r = transform.docToNDC(x: inner.maxX, y: y)
                baselineVerts.append(contentsOf: [l, r])
                y += step
            }
            if !baselineVerts.isEmpty {
                encoder.setVertexBytes(baselineVerts, length: baselineVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
                var colorBase = SIMD4<Float>(0.90,0.92,0.95,1)
                encoder.setFragmentBytes(&colorBase, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
                encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: baselineVerts.count)
            }
        }
        // 4) Page border (hairline)
        var borderVerts: [SIMD2<Float>] = []
        borderVerts.append(contentsOf: [tl, tr, tr, br, br, bl, bl, tl])
        encoder.setVertexBytes(borderVerts, length: borderVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var colorBorder = SIMD4<Float>(0.65,0.68,0.72,1)
        encoder.setFragmentBytes(&colorBorder, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: borderVerts.count)
    }
    public static func pageSize(_ page: String) -> CGSize { page.lowercased() == "letter" ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842) }
    public static func baselineCount(page: String, margins: MVKMargins, baseline: CGFloat) -> Int {
        let h = pageSize(page).height
        let usable = max(0, h - margins.top - margins.bottom)
        return max(1, Int(floor(usable / max(1, baseline))))
    }
}

#endif
