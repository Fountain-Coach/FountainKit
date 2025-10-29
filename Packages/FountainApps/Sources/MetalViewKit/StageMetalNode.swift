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
        let size = StageMetalNode.pageSize(page)
        let count = StageMetalNode.baselineCount(page: page, margins: margins, baseline: baseline)
        guard count > 0 else { return [] }
        // Map baseline midpoints to node-local coordinates
        var ports: [MetalNodePort] = []
        let left = margins.left
        let top = margins.top
        let innerH = size.height - margins.top - margins.bottom
        let fractions = (0..<count).map { CGFloat($0 + 1) / CGFloat(count + 1) }
        for (i,f) in fractions.enumerated() {
            let y = top + innerH * f
            ports.append(.init(id: "in\(i)", side: .left, dir: .input, centerLocal: CGPoint(x: left, y: y)))
        }
        return ports
    }
    public func encode(into view: MTKView, device: MTLDevice, commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor) {
        // Minimal stub: clear is handled by the canvas; Stage draws via a simple grid in a separate render pipeline in future commits.
        // For now no-op keeps compilation while protocol solidifies.
    }
    public static func pageSize(_ page: String) -> CGSize { page.lowercased() == "letter" ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842) }
    public static func baselineCount(page: String, margins: MVKMargins, baseline: CGFloat) -> Int {
        let h = pageSize(page).height
        let usable = max(0, h - margins.top - margins.bottom)
        return max(1, Int(floor(usable / max(1, baseline))))
    }
}

#endif
