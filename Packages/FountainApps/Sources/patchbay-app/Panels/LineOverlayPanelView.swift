import SwiftUI
import Charts

struct LineOverlayPanelView: View {
    var title: String
    var series: [TimeSeries]
    var annotations: [Annotation]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(0..<series.count, id: \.self) { idx in
                    let s = series[idx]
                    ForEach(s.points, id: \.0) { p in
                        LineMark(x: .value("Time", p.0), y: .value("Value", p.1))
                            .foregroundStyle(by: .value("Series", idx))
                    }
                }
                ForEach(annotations) { a in
                    RuleMark(x: .value("Time", a.time))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,2]))
                        .foregroundStyle(.red)
                        .annotation(position: .top, alignment: .leading) { Text(a.text).font(.caption2) }
                }
            }
        }
        .padding(6)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}

