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
    let overlays: [Overlay]

    public init(title: String, overlays: [Overlay]) {
        self.title = title
        self.overlays = overlays
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack { Text(title).font(.headline); Spacer() }
            GeometryReader { geo in
                ZStack {
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

                    // Overlays (normalized → pixel space)
                    ForEach(overlays) { ov in
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

            HStack(spacing: 12) {
                legend(color: .green, label: "Covered")
                legend(color: .orange, label: "Stale")
                legend(color: .red, label: "Missing")
                Spacer()
                Text("Mock preview — snapshot overlays pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color.opacity(0.5)).frame(width: 14, height: 10).overlay(Rectangle().stroke(color, lineWidth: 1))
            Text(label).font(.caption)
        }
    }
}

