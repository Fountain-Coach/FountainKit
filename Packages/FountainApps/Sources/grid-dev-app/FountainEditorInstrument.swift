import SwiftUI
import Teatro

struct FountainEditorInstrument: View {
    @Binding var text: String
    @State private var parsedCount: Int = 0
    @State private var lastError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fountain Editor").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("lines: \(text.split(separator: "\n", omittingEmptySubsequences: false).count)").font(.system(size: 11)).opacity(0.6)
                Text("nodes: \(parsedCount)").font(.system(size: 11)).opacity(0.6)
            }
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 240)
                .border(Color(nsColor: .separatorColor))
                .onChange(of: text) { _, newValue in
                    parseAsync(newValue)
                }
            if let err = lastError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .onAppear { parseAsync(text) }
    }

    private func parseAsync(_ s: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = FountainParser()
            let nodes = p.parse(s)
            DispatchQueue.main.async {
                self.parsedCount = nodes.count
                self.lastError = nil
                // Emit a monitor snapshot for parity
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                    "type": "text.parsed", "nodes": nodes.count
                ])
            }
        }
    }
}

