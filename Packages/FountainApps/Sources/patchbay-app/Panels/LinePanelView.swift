import SwiftUI
import Charts

struct LinePanelView: View {
    var series: [TimeSeries]
    var title: String

    struct Sample: Identifiable { let id = UUID(); let time: Date; let value: Double }

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
            }
            .chartXAxis(.automatic)
            .chartYAxis(.automatic)
        }
        .padding(6)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}

