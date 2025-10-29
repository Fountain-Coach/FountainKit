import SwiftUI

struct StatPanelView: View {
    var title: String
    var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}

