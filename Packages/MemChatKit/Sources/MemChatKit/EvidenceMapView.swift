import SwiftUI

public struct EvidenceMapView: View {
    public struct Overlay: Identifiable, Sendable, Equatable {
        public let id: String
        public let rect: CGRect   // normalized 0..1 in both axes
        public let color: Color
        public init(id: String, rect: CGRect, color: Color) {
            self.id = id
            self.rect = rect
            self.color = color
        }
    }

    let title: String
    let imageURL: URL?
    let covered: [Overlay]
    let stale: [Overlay]
    let missing: [Overlay]
    @State private var showCovered = true
    @State private var showStale = true
    @State private var showMissing = false
    @State private var initialCoverage: Double? = nil

    public init(title: String, overlays: [Overlay]) {
        self.title = title
        self.imageURL = nil
        self.covered = overlays
        self.stale = []
        self.missing = []
    }

    public init(title: String, imageURL: URL?, covered: [Overlay], stale: [Overlay] = [], missing: [Overlay] = [], initialCoverage: Double? = nil) {
        self.title = title
        self.imageURL = imageURL
        self.covered = covered
        self.stale = stale
        self.missing = missing
        self._initialCoverage = State(initialValue: initialCoverage)
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack { Text(title).font(.headline); Spacer() }
            GeometryReader { geo in
                ZStack {
                    if let url = imageURL {
                        // Render truth image if available
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ZStack { Rectangle().fill(Color.gray.opacity(0.06)); ProgressView() }
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(8)
                            case .failure:
                                Rectangle().fill(Color.gray.opacity(0.08)).cornerRadius(8)
                            @unknown default:
                                Rectangle().fill(Color.gray.opacity(0.08)).cornerRadius(8)
                            }
                        }
                    } else {
                        // Placeholder canvas
                        Rectangle()
                            .fill(Color.gray.opacity(0.08))
                            .overlay(
                                VStack(spacing: 0) {
                                    ForEach(0..<12, id: \.self) { _ in
                                        Rectangle().fill(Color.gray.opacity(0.05)).frame(height: 1)
                                        Spacer()
                                    }
                                }
                            )
                            .cornerRadius(8)
                    }

                    // Overlays (normalized → pixel space)
                    ForEach(visibleOverlays) { ov in
                        let r = CGRect(x: ov.rect.origin.x * geo.size.width,
                                       y: ov.rect.origin.y * geo.size.height,
                                       width: ov.rect.size.width * geo.size.width,
                                       height: ov.rect.size.height * geo.size.height)
                        Rectangle()
                            .strokeBorder(ov.color.opacity(0.9), lineWidth: 2)
                            .background(Rectangle().fill(ov.color.opacity(0.15)))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .accessibilityLabel(Text(ov.id))
                    }
                }
            }
            .frame(minHeight: 360)

            HStack(spacing: 14) {
                Toggle(isOn: $showCovered) { legend(color: .green, label: "Covered (\(covered.count))") }.toggleStyle(.checkbox)
                Toggle(isOn: $showStale) { legend(color: .orange, label: "Stale (\(stale.count))") }.toggleStyle(.checkbox)
                Toggle(isOn: $showMissing) { legend(color: .red, label: "Missing (\(missing.count))") }.toggleStyle(.checkbox)
                Spacer()
                let cov = coveragePercent
                Text("Coverage: \(Int(round(cov * 100)))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private var visibleOverlays: [Overlay] {
        var out: [Overlay] = []
        if showCovered { out.append(contentsOf: covered) }
        if showStale { out.append(contentsOf: stale) }
        if showMissing { out.append(contentsOf: missing) }
        return out
    }

    private var coveragePercent: Double {
        if let initial = initialCoverage { return min(max(initial, 0.0), 1.0) }
        // Approximate coverage using union area of covered overlays only
        let area = VisualCoverageUtils.unionAreaNormalized(covered.map { $0.rect })
        return min(max(Double(area), 0.0), 1.0)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color.opacity(0.5)).frame(width: 14, height: 10).overlay(Rectangle().stroke(color, lineWidth: 1))
            Text(label).font(.caption)
        }
    }
}

public enum VisualCoverageUtils {
    /// Compute the union area of normalized rects (0..1 axes).
    /// Uses a vertical sweep-line over unique x edges.
    public static func unionAreaNormalized(_ rects: [CGRect]) -> CGFloat {
        let filtered = rects.map { clamp($0) }.filter { $0.width > 0 && $0.height > 0 }
        guard !filtered.isEmpty else { return 0 }
        // Collect unique x boundaries
        var xs = Array(Set(filtered.flatMap { [$0.minX, $0.maxX] }))
        xs.sort()
        var area: CGFloat = 0
        for i in 0..<(xs.count - 1) {
            let x1 = xs[i], x2 = xs[i+1]
            let w = x2 - x1
            if w <= 0 { continue }
            // Collect y-intervals for rects spanning this x-strip
            var intervals: [(CGFloat, CGFloat)] = []
            for r in filtered where r.minX < x2 && r.maxX > x1 {
                intervals.append((r.minY, r.maxY))
            }
            if intervals.isEmpty { continue }
            intervals.sort { $0.0 < $1.0 }
            var coveredY: CGFloat = 0
            var curStart = intervals[0].0
            var curEnd = intervals[0].1
            for (y1, y2) in intervals.dropFirst() {
                if y1 <= curEnd { curEnd = max(curEnd, y2) }
                else { coveredY += max(0, curEnd - curStart); curStart = y1; curEnd = y2 }
            }
            coveredY += max(0, curEnd - curStart)
            area += w * coveredY
        }
        // Clamp area just in case of numeric noise
        return max(0, min(1, area))
    }
    private static func clamp(_ r: CGRect) -> CGRect {
        let x = max(0, min(1, r.origin.x))
        let y = max(0, min(1, r.origin.y))
        let w = max(0, min(1 - x, r.size.width))
        let h = max(0, min(1 - y, r.size.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
