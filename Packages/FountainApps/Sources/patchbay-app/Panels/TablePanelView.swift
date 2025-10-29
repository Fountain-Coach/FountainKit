import SwiftUI

struct TablePanelView: View {
    var title: String
    var rows: [TableRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { r in
                    HStack { Text(r.label); Spacer(); Text(String(format: "%.2f", r.value)).monospacedDigit() }
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}

