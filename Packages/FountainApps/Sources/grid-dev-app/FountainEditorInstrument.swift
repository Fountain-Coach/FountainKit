import SwiftUI
import Teatro

struct FountainEditorInstrument: View {
    @Binding var text: String
    @State private var parsedCount: Int = 0
    @State private var lastError: String? = nil
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fountain Editor").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("lines: \(text.split(separator: "\n", omittingEmptySubsequences: false).count)").font(.system(size: 11)).opacity(0.6)
                Text("nodes: \(parsedCount)").font(.system(size: 11)).opacity(0.6)
            }
            ZStack(alignment: .topLeading) {
                // A4 placeholder always behind; editor overlays it
                ZStack {
                    Color(red: 0.96, green: 0.97, blue: 0.98)
                    VStack { Spacer(minLength: 8)
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white)
                                .frame(width: 595, height: 842)
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
                            if text.isEmpty {
                                Text("A4").font(.system(size: 11)).foregroundStyle(.secondary).opacity(0.4).offset(y: 360)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                }
                .frame(minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($isEditing)
                    .background(Color.clear)
                    .opacity(text.isEmpty ? 0.02 : 1.0) // accept focus even when empty
                    .frame(minHeight: 260)
                    .border(Color(nsColor: .separatorColor).opacity(text.isEmpty ? 0 : 1))
                    .onChange(of: text) { _, newValue in
                        parseAsync(newValue)
                    }
                if text.isEmpty {
                    Text("Click to start typing…")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(6).background(.ultraThinMaterial).cornerRadius(6)
                        .padding(8)
                        .onTapGesture { isEditing = true }
                }
            }
            if let err = lastError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .onAppear { parseAsync(text); isEditing = true }
    }

    private func parseAsync(_ s: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Lightweight heuristic parser to avoid external dependency
            // Counts simple Fountain-like constructs by prefixes
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            var count = 0
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                if t.hasPrefix("INT.") || t.hasPrefix("EXT.") || t == t.uppercased() || t.hasPrefix("CUT TO:") {
                    count += 1
                } else {
                    // count other non-empty lines as nodes coarse-grained
                    count += 1
                }
            }
            DispatchQueue.main.async {
                self.parsedCount = count
                self.lastError = nil
                // Emit a monitor snapshot for parity
                NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
                    "type": "text.parsed", "nodes": count
                ])
            }
        }
    }
}
