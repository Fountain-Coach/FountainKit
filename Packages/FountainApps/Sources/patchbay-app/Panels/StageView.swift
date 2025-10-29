import SwiftUI

struct StageView: View {
    var title: String
    var page: String = "A4" // or "Letter"
    var margins: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    var baseline: CGFloat = 12

    private var pageSize: CGSize {
        switch page.lowercased() {
        case "letter": return CGSize(width: 612, height: 792) // 8.5x11 at 72dpi
        default: return CGSize(width: 595, height: 842) // A4 210x297mm at 72dpi
        }
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / pageSize.width, geo.size.height / pageSize.height)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white)
                    .frame(width: pageSize.width, height: pageSize.height)
                    .shadow(radius: 4)
                // Margin guides
                Path { p in
                    let r = CGRect(origin: .zero, size: pageSize).insetBy(dx: margins.leading, dy: margins.top)
                        .insetBy(dx: margins.trailing, dy: margins.bottom)
                    p.addRect(r)
                }
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4,3]))
                // Baseline grid
                Canvas { ctx, size in
                    let r = CGRect(x: margins.leading,
                                   y: margins.top,
                                   width: pageSize.width - margins.leading - margins.trailing,
                                   height: pageSize.height - margins.top - margins.bottom)
                    var y: CGFloat = r.minY
                    let step = max(6, baseline)
                    let lineColor = Color.gray.opacity(0.1)
                    while y <= r.maxY {
                        var path = Path()
                        path.move(to: CGPoint(x: r.minX, y: y))
                        path.addLine(to: CGPoint(x: r.maxX, y: y))
                        ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                        y += step
                    }
                }
                .frame(width: pageSize.width, height: pageSize.height)
                // Title / placeholder
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title3).bold()
                    Text("The Stage — A4 preview").font(.caption).foregroundStyle(.secondary)
                }
                .padding(EdgeInsets(top: margins.top+8, leading: margins.leading+8, bottom: 0, trailing: 0))
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}
