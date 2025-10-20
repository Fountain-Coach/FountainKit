import Foundation
import SemanticBrowserAPI
import SwiftUI

enum VisualDiffBuilder {
    /// Classify analysis blocks into covered vs missing using simple text overlap against provided evidence texts.
    /// - Parameters:
    ///   - analysis: Analysis from Semantic Browser
    ///   - imageId: The image these rects belong to
    ///   - evidenceTexts: Textual evidence snippets already stored for the host
    ///   - minOverlap: Token overlap threshold (0..1)
    /// - Returns: Covered and missing overlays
    static func classify(
        analysis: SemanticBrowserAPI.Components.Schemas.Analysis,
        imageId: String,
        evidenceTexts: [String],
        minOverlap: Double = 0.2
    ) -> (covered: [EvidenceMapView.Overlay], missing: [EvidenceMapView.Overlay]) {
        let evBags: [[String: Int]] = evidenceTexts.map { bagOfWords($0) }
        var covered: [EvidenceMapView.Overlay] = []
        var missing: [EvidenceMapView.Overlay] = []
        for b in analysis.blocks {
            guard let rects = b.rects, !rects.isEmpty else { continue }
            let bag = bagOfWords(b.text ?? "")
            // Compute best overlap across evidence
            let best: Double = evBags.map { jaccard(bag, $0) }.max() ?? 0
            let color: Color = best >= minOverlap ? .green : .red
            for (i, r) in rects.enumerated() where r.imageId == imageId {
                let rect = CGRect(x: CGFloat(r.x ?? 0), y: CGFloat(r.y ?? 0), width: CGFloat(r.w ?? 0), height: CGFloat(r.h ?? 0))
                guard rect.width > 0, rect.height > 0 else { continue }
                let overlay = EvidenceMapView.Overlay(id: "\(b.id)-\(i)", rect: rect, color: color)
                if color == .green { covered.append(overlay) } else { missing.append(overlay) }
            }
        }
        return (covered, missing)
    }

    private static func bagOfWords(_ s: String) -> [String: Int] {
        let tokens = s.lowercased().replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
        var bag: [String: Int] = [:]
        for t in tokens { bag[t, default: 0] += 1 }
        return bag
    }
    private static func jaccard(_ a: [String: Int], _ b: [String: Int]) -> Double {
        let keys = Set(a.keys).union(b.keys)
        var inter: Double = 0
        var uni: Double = 0
        for k in keys {
            let av = Double(a[k] ?? 0)
            let bv = Double(b[k] ?? 0)
            inter += min(av, bv)
            uni += max(av, bv)
        }
        if uni == 0 { return 0 }
        return inter / uni
    }
}

