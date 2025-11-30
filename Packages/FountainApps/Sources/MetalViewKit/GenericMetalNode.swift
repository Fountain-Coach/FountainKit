// GenericMetalNode — minimal rectangle node with side ports

#if canImport(AppKit) && canImport(Metal) && canImport(MetalKit)
import Foundation
import CoreGraphics
import Metal
import MetalKit

public final class GenericMetalNode: MetalCanvasNode {
    public let id: String
    public var frameDoc: CGRect
    public var inPorts: [String]
    public var outPorts: [String]
    public init(id: String, frameDoc: CGRect, inPorts: [String], outPorts: [String]) {
        self.id = id; self.frameDoc = frameDoc; self.inPorts = inPorts; self.outPorts = outPorts
    }
    public func portLayout() -> [MetalNodePort] { [] } // not used (we provide doc centers directly)
    public func portDocCenters() -> [MetalNodePortCenter] {
        var out: [MetalNodePortCenter] = []
        let midY = frameDoc.midY
        // place a single left/right port if arrays non-empty; additional ports stack with small offsets
        let step: CGFloat = 14
        for (i,idp) in inPorts.enumerated() {
            let cy = midY + CGFloat(i - inPorts.count/2) * step
            out.append(.init(id: idp, dir: .input, side: .left, doc: CGPoint(x: frameDoc.minX, y: cy)))
        }
        for (i,idp) in outPorts.enumerated() {
            let cy = midY + CGFloat(i - outPorts.count/2) * step
            out.append(.init(id: idp, dir: .output, side: .right, doc: CGPoint(x: frameDoc.maxX, y: cy)))
        }
        return out
    }
    public func encode(into view: MTKView, device: MTLDevice, encoder: MTLRenderCommandEncoder, transform: MetalCanvasTransform) {
        // Body fill
        let tl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.minY)
        let tr = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.minY)
        let bl = transform.docToNDC(x: frameDoc.minX, y: frameDoc.maxY)
        let br = transform.docToNDC(x: frameDoc.maxX, y: frameDoc.maxY)
        let fillVerts: [SIMD2<Float>] = [tl, bl, tr, tr, bl, br]
        encoder.setVertexBytes(fillVerts, length: fillVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var colorFill = SIMD4<Float>(0.97,0.97,0.985,1)
        encoder.setFragmentBytes(&colorFill, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        // Border
        let borderVerts: [SIMD2<Float>] = [tl, tr, tr, br, br, bl, bl, tl]
        encoder.setVertexBytes(borderVerts, length: borderVerts.count * MemoryLayout<SIMD2<Float>>.stride, index: 0)
        var colorBorder = SIMD4<Float>(0.70,0.73,0.78,1)
        encoder.setFragmentBytes(&colorBorder, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: borderVerts.count)
    }
}

#endif
