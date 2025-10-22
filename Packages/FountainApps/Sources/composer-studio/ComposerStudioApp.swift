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
    @State private var chat: [ChatMessage] = [
        .init(role: .assistant, text: "Welcome. Type your screenplay, then tell me what you want musically.")
    ]
    @State private var showReadyPulse: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Project", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                readyBadge
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
                // Right: chat + analysis results
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat").font(.subheadline)
                    ChatView(messages: $chat, onSend: handleSend)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    HStack(alignment: .top, spacing: 8) {
                        resultCard(title: "Analysis", text: parseSummary)
                        resultCard(title: "Cues", text: cuesSummary)
                    }
                    resultCard(title: "Apply", text: applySummary)
                }
                .frame(minWidth: 360)
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

    // Subviews
    private var readyBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(showReadyPulse ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: showReadyPulse)
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { showReadyPulse = true }
    }

    private func resultCard(title: String, text: String) -> some View {
        GroupBox(label: Text(title)) { ScrollView { Text(text.isEmpty ? "(no data)" : text).font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) } }.frame(minWidth: 260, minHeight: 160)
    }

    // MARK: - Placeholder logic (fresh start)
    private func bootstrap() {
        parseSummary = ""; cuesSummary = ""; applySummary = ""; journal = []
        if let saved = UserDefaults.standard.string(forKey: "ComposerStudio.Screenplay") { screenplay = saved }
        if let name = UserDefaults.standard.string(forKey: "ComposerStudio.ProjectName") { projectName = name }
    }
    private func analyze() {
        // Placeholder: in real app call parse + map endpoints
        withAnimation(.spring()) {
            parseSummary = "Parsed screenplay: scenes=1 beats=0 notes=1 (mood gentle)\nWarnings: 0"
            cuesSummary = "Generated cues: 1\n- mood gentle → dynamics:p, tempo:moderato"
        }
        saveDraft()
        journal.insert("analyzed project=\(projectName)", at: 0)
    }
    private func applyToScore() {
        withAnimation(.easeInOut) { applySummary = "Applied 1 cue to score (ok)" }
        journal.insert("applied cues count=1", at: 0)
    }
    private func handleSend(_ text: String) {
        withAnimation { chat.append(.init(role: .user, text: text)) }
        // Very small assistant simulation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let preview = "Plan: \(text) → 1 cue\nPreview: mood gentle → p, moderato\n[Apply]"
            withAnimation { chat.append(.init(role: .assistant, text: preview)) }
        }
    }
    private func saveDraft() {
        UserDefaults.standard.set(screenplay, forKey: "ComposerStudio.Screenplay")
        UserDefaults.standard.set(projectName, forKey: "ComposerStudio.ProjectName")
    }
}
#else
@main
enum ComposerStudioUnavailable {
    static func main() { fputs("ComposerStudio requires macOS.\n", stderr) }
}
#endif
