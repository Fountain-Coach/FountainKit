import SwiftUI

struct PlanPreviewCard: View {
    let analysis: String
    let cues: String
    let apply: String
    var onApply: () -> Void
    @State private var tab: Tab = .analysis
    enum Tab: String, CaseIterable { case analysis = "Analysis", cues = "Cues", apply = "Apply" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview").font(.subheadline)
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                if tab != .apply { Button("Apply") { onApply(); tab = .apply }.keyboardShortcut(.return, modifiers: [.command]) }
            }
            GroupBox(label: Text(tab.rawValue)) {
                ScrollView {
                    Text(textForTab())
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func textForTab() -> String {
        switch tab { case .analysis: return analysis.isEmpty ? "(no data)" : analysis
        case .cues: return cues.isEmpty ? "(no data)" : cues
        case .apply: return apply.isEmpty ? "(no data)" : apply }
    }
}

