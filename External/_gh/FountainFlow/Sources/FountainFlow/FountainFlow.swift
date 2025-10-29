import Foundation
import CoreGraphics
import SwiftUI
import Flow

/// FountainFlow — initial surface.
///
/// Goal: provide per-node style and rect providers on top of Flow, evolving to a native editor.
public enum FountainFlowAPI {
    /// Marker type for the package; expanded as we migrate.
}

/// A node kind hint for conditional body/port rendering.
public enum NodeKindHint: Equatable {
    case stage
    case generic
}

/// Per-node style provider surface (v0 draft).
public protocol NodeStyleProvider {
    func drawBody(for index: Int) -> Bool
    func nodeKind(for index: Int) -> NodeKindHint
}

/// Per-node rect provider surface (v0 draft).
public protocol NodeRectProvider {
    /// Returns the rect for the node body in document coordinates.
    func nodeRect(for index: Int) -> CGRect
    /// Returns the input port rect for a given input index in document coordinates.
    func inputRect(for index: Int, input: Int) -> CGRect
    /// Returns the output port rect for a given output index in document coordinates.
    func outputRect(for index: Int, output: Int) -> CGRect
}

// MARK: - Stage primitives (v0)

public struct StageNodeModel: Identifiable, Equatable {
    public var id: String
    public var rectDoc: CGRect
    public var title: String
    public var page: String // "A4" or "Letter"
    public var margins: EdgeInsets
    public var baseline: CGFloat
    public var selected: Bool
    public init(id: String, rectDoc: CGRect, title: String, page: String, margins: EdgeInsets, baseline: CGFloat, selected: Bool) {
        self.id = id; self.rectDoc = rectDoc; self.title = title; self.page = page; self.margins = margins; self.baseline = baseline; self.selected = selected
    }
}

public enum StageGeometry {
    public static func pageSizePoints(_ page: String) -> CGSize {
        switch page.lowercased() {
        case "letter": return CGSize(width: 612, height: 792) // 8.5x11in @72dpi
        default: return CGSize(width: 595, height: 842) // A4 @72dpi
        }
    }
    public static func baselineCount(page: String, margins: EdgeInsets, baseline: CGFloat) -> Int {
        let h = pageSizePoints(page).height
        let usable = max(0, h - margins.top - margins.bottom)
        return max(1, Int(floor(usable / max(1, baseline))))
    }
}

public struct StageRenderer: View {
    public var title: String
    public var page: String
    public var margins: EdgeInsets
    public var baseline: CGFloat
    public init(title: String, page: String, margins: EdgeInsets, baseline: CGFloat) {
        self.title = title; self.page = page; self.margins = margins; self.baseline = baseline
    }
    public var body: some View {
        let size = StageGeometry.pageSizePoints(page)
        let count = StageGeometry.baselineCount(page: page, margins: margins, baseline: baseline)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.white)
                .overlay(
                    // Margin guides
                    Rectangle()
                        .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
                        .padding(EdgeInsets(top: margins.top, leading: margins.leading, bottom: margins.bottom, trailing: margins.trailing))
                )
            // Baselines
            Canvas { cx, sz in
                let scaleX = sz.width / size.width
                let scaleY = sz.height / size.height
                let scale = min(scaleX, scaleY)
                let left = margins.leading * scale
                let top = margins.top * scale
                let innerW = (size.width - margins.leading - margins.trailing) * scale
                let innerH = (size.height - margins.top - margins.bottom) * scale
                let spacing = baseline * scale
                var y = top + spacing
                let minor = Color.gray.opacity(0.12)
                let major = Color.gray.opacity(0.18)
                var idx = 1
                while y <= top + innerH - 0.5 {
                    var p = Path(); p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: left + innerW, y: y))
                    cx.stroke(p, with: .color((idx % 5 == 0) ? major : minor), lineWidth: 1)
                    y += spacing; idx += 1
                }
            }
        }
    }
}

public struct StageOverlayHost: View {
    public var stages: [StageNodeModel]
    public var zoom: CGFloat
    public var translation: CGPoint
    public var showBaselineIndex: Bool
    public var alwaysShow: Bool
    public var oneBased: Bool
    public init(stages: [StageNodeModel], zoom: CGFloat, translation: CGPoint, showBaselineIndex: Bool, alwaysShow: Bool, oneBased: Bool) {
        self.stages = stages; self.zoom = zoom; self.translation = translation; self.showBaselineIndex = showBaselineIndex; self.alwaysShow = alwaysShow; self.oneBased = oneBased
    }
    private func docToView(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + translation.x * zoom, y: p.y * zoom + translation.y * zoom) }
    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(stages) { s in
                let originView = docToView(CGPoint(x: s.rectDoc.minX, y: s.rectDoc.minY))
                let rectView = CGRect(x: originView.x, y: originView.y, width: s.rectDoc.width * zoom, height: s.rectDoc.height * zoom)
                StageRenderer(title: s.title, page: s.page, margins: s.margins, baseline: s.baseline)
                    .frame(width: rectView.width, height: rectView.height, alignment: .topLeading)
                    .position(x: rectView.minX, y: rectView.minY)
                    .allowsHitTesting(false)
                if showBaselineIndex && (alwaysShow || s.selected) {
                    let count = StageGeometry.baselineCount(page: s.page, margins: s.margins, baseline: s.baseline)
                    ForEach(0..<count, id: \.self) { idx in
                        let k = oneBased ? (idx + 1) : idx
                        let frac = CGFloat(idx + 1) / CGFloat(count + 1)
                        let y = rectView.minY + rectView.height * frac
                        let x = rectView.minX + 6
                        Text("\(k)")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .position(x: x, y: y)
                            .allowsHitTesting(false)
                            .accessibilityLabel(Text("Stage \(s.title), input \(k) of \(count)"))
                    }
                }
            }
        }
    }
}

