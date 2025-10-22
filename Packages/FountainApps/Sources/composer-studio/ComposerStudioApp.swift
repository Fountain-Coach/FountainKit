import Foundation
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

@main
struct ComposerStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ComposerRootView()
                .onAppear { if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) } }
        }
    }
}

struct ComposerRootView: View {
    @State private var projectName: String = "Untitled"
    @State private var screenplay: String = """
Title: A New Piece

INT. ROOM — DAY

The composer sits at the desk.

[[AudioTalk: mood gentle]]

"""
    @State private var parseSummary: String = ""
    @State private var cuesSummary: String = ""
    @State private var applySummary: String = ""
    @State private var journal: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Project", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Spacer()
                Button("Analyze") { analyze() }
                Button("Apply to Score") { applyToScore() }
            }
            .font(.callout)
            HSplitView {
                // Left: screenplay editor
                VStack(alignment: .leading) {
                    Text("Screenplay").font(.subheadline)
                    TextEditor(text: $screenplay)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 320)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                }
                // Right: analysis results
                VStack(alignment: .leading, spacing: 8) {
                    resultCard(title: "Analysis", text: parseSummary)
                    resultCard(title: "Cues", text: cuesSummary)
                    resultCard(title: "Apply", text: applySummary)
                }.frame(minWidth: 320)
            }
            GroupBox(label: Text("Journal")) {
                ScrollView { VStack(alignment: .leading, spacing: 4) { ForEach(journal, id: \.self) { Text($0).font(.caption) } } }.frame(minHeight: 120)
            }
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 880, minHeight: 560)
        .onAppear { bootstrap() }
    }

    private func resultCard(title: String, text: String) -> some View {
        GroupBox(label: Text(title)) { ScrollView { Text(text.isEmpty ? "(no data)" : text).font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) } }.frame(minWidth: 260, minHeight: 160)
    }

    // MARK: - Placeholder logic (fresh start)
    private func bootstrap() {
        parseSummary = ""; cuesSummary = ""; applySummary = ""; journal = []
    }
    private func analyze() {
        // Placeholder: in real app call parse + map endpoints
        parseSummary = "Parsed screenplay: scenes=1 beats=0 notes=1 (mood gentle)\nWarnings: 0"
        cuesSummary = "Generated cues: 1\n- mood gentle → dynamics:p, tempo:moderato"
        journal.insert("analyzed project=\(projectName)", at: 0)
    }
    private func applyToScore() {
        applySummary = "Applied 1 cue to score (ok)"
        journal.insert("applied cues count=1", at: 0)
    }
}
#else
@main
enum ComposerStudioUnavailable {
    static func main() { fputs("ComposerStudio requires macOS.\n", stderr) }
}
#endif
