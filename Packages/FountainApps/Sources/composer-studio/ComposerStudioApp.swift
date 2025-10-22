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
    @State private var sessionID: String = ""
    @State private var etag: String = "–"
    @State private var updatedAt: String = "–"
    @State private var canParse = false
    @State private var canMap = false
    @State private var canApply = false
    @State private var parseResult: String = ""
    @State private var mapResult: String = ""
    @State private var applyResult: String = ""
    @State private var journal: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Composer Studio").font(.title3).bold()
                Spacer()
                Text("Session:")
                TextField("id", text: $sessionID).frame(width: 160)
                Button("New") { newSession() }
            }
            HStack(spacing: 12) {
                label("ETag", etag)
                label("Updated", updatedAt)
                Spacer()
            }.font(.caption)
            Divider()
            HStack(spacing: 8) {
                Button("Parse") { doParse() }.disabled(!canParse)
                Button("Map Cues") { doMap() }.disabled(!canMap)
                Button("Apply") { doApply() }.disabled(!canApply)
            }
            .font(.callout)
            HStack(alignment: .top, spacing: 12) {
                resultCard(title: "Parse", text: parseResult)
                resultCard(title: "Map", text: mapResult)
                resultCard(title: "Apply", text: applyResult)
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

    private func label(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) { Text(name+":").foregroundStyle(.secondary); Text(value) }
    }
    private func resultCard(title: String, text: String) -> some View {
        GroupBox(label: Text(title)) { ScrollView { Text(text.isEmpty ? "(no data)" : text).font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) } }.frame(minWidth: 260, minHeight: 160)
    }

    // MARK: - Placeholder logic (fresh start)
    private func bootstrap() {
        // Fresh start defaults (no network calls here yet)
        canParse = false; canMap = false; canApply = false
        parseResult = ""; mapResult = ""; applyResult = ""; journal = []
    }
    private func newSession() {
        sessionID = UUID().uuidString.prefix(8).description
        etag = "(none)"; updatedAt = Date.now.formatted();
        canParse = true; canMap = false; canApply = false
        journal.insert("session_created id=\(sessionID)", at: 0)
    }
    private func doParse() {
        // WIP: wire to /screenplay/{id}/parse; here we just simulate
        etag = UUID().uuidString.prefix(7).description
        updatedAt = Date.now.formatted()
        parseResult = "model: scenes=0 beats=0 notes=0\nwarnings: 0"
        canMap = true; canApply = false
        journal.insert("parsed etag=\(etag)", at: 0)
    }
    private func doMap() {
        mapResult = "cues: 0"
        canApply = true
        journal.insert("cues_mapped count=0", at: 0)
    }
    private func doApply() {
        applyResult = "applied: ok"
        journal.insert("applied ok", at: 0)
    }
}
#else
@main
enum ComposerStudioUnavailable {
    static func main() { fputs("ComposerStudio requires macOS.\n", stderr) }
}
#endif

