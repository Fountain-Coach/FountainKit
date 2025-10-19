import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import FountainAIKit

/// Drop-in SwiftUI view for MemChat.
/// Host apps can either use this directly or compose their own view while
/// holding a reference to `MemChatController`.
public struct MemChatView: View {
    @StateObject private var controller: MemChatController
    @State private var input: String = ""
    @State private var strictOn: Bool = false
    @FocusState private var inputFocused: Bool

    public init(configuration: MemChatConfiguration) {
        _controller = StateObject(wrappedValue: MemChatController(config: configuration))
    }

    public init(controller: MemChatController) {
        _controller = StateObject(wrappedValue: controller)
    }

    public var body: some View {
#if os(macOS)
        HSplitView {
            // 1) Chats list (semantic, named sessions)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(controller.chatTitle ?? "MemChat").font(.title3).bold()
                        Spacer()
                        // Strict Memory Mode toggle
                        Toggle(isOn: $strictOn) { Text("Strict") }
                            .toggleStyle(.switch)
                            .help("Strict Memory Mode: answer strictly from stored site memory with citations")
                            .onChange(of: strictOn) { on in controller.setStrictMemoryMode(on) }
                        Button("Reset") { Task { _ = await controller.resetMemoryCorpus() } }
                            .disabled(controller.state == .streaming)
                        Button("New Chat") { controller.newChat() }
                            .disabled(controller.state == .streaming)
                    }
                    .padding(.bottom, 4)

                    if let err = controller.lastError, !err.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            Text(err).font(.caption)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.yellow.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if controller.sessionOverviews.isEmpty {
                        Text("No saved chats yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(controller.sessionOverviews.sorted(by: { $0.updatedAt > $1.updatedAt })) { s in
                                Button(action: { controller.openChatSession(s.id) }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(s.title).font(.callout)
                                        Text(s.lastAnswerPreview)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(s.isCurrentSession ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2))
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(minHeight: 120)

            // 2) Transcript pane (scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if controller.config.showSemanticPanel, let panel = controller.semanticPanel {
                        GroupBox(label: Text("Semantic Panel").font(.caption2)) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let t = panel.topicName, !t.isEmpty {
                                    Text("Topic: \(t)").font(.callout.weight(.semibold))
                                }
                                if !panel.stepstones.isEmpty {
                                    Text("Stepstones").font(.caption).foregroundStyle(.secondary)
                                    ForEach(Array(panel.stepstones.prefix(7).enumerated()), id: \.offset) { _, s in
                                        Text("• \(s)")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                if controller.config.showSources, !panel.sources.isEmpty {
                                    Text("Sources").font(.caption).foregroundStyle(.secondary)
                                    ForEach(panel.sources) { src in
                                        Text("• \(src.title)")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                    // Evidence: What we learned (recent cited segments)
                    if !controller.recentEvidence.isEmpty {
                        GroupBox(label: Text("What we learned").font(.caption2)) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(controller.recentEvidence.prefix(8).enumerated()), id: \.offset) { _, e in
                                    Text("• \(e.text) — \(e.title)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    ForEach(controller.turns, id: \.id) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("You").font(.caption).foregroundStyle(.secondary)
                            Text(t.prompt)
                            Divider()
                            Text("Assistant").font(.caption).foregroundStyle(.secondary)
                            Text(t.answer)
                            if let ctx = controller.turnContext[t.id] {
                                Divider().padding(.vertical, 4)
                                DisclosureGroup("Context used") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let cont = ctx.continuity, !cont.isEmpty {
                                            GroupBox(label: Text("ContinuityDigest").font(.caption2)) {
                                                Text(cont)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        if let sum = ctx.awarenessSummary, !sum.isEmpty {
                                            GroupBox(label: Text("Awareness Summary").font(.caption2)) {
                                                Text(sum)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        if let hist = ctx.awarenessHistory, !hist.isEmpty {
                                            GroupBox(label: Text("History Overview").font(.caption2)) {
                                                Text(hist)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        if !ctx.snippets.isEmpty {
                                            GroupBox(label: Text("Memory Snippets").font(.caption2)) {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    ForEach(Array(ctx.snippets.enumerated()), id: \.offset) { _, s in
                                                        Text("• \(s)")
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06))
                        )
                    }
                    if !controller.streamingText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Streaming…").font(.caption).foregroundStyle(.secondary)
                            Text(controller.streamingText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.35))
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(minHeight: 220)

            // 3) Inspector + Composer (right pane)
            VStack(alignment: .leading, spacing: 12) {
                // Memory Context Inspector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Memory Context Inspector").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let ctx = controller.lastInjectedContext {
                                if let cont = ctx.continuity, !cont.isEmpty {
                                    GroupBox(label: Text("ContinuityDigest").font(.caption2)) {
                                        Text(cont).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                if let sum = ctx.awarenessSummary, !sum.isEmpty {
                                    GroupBox(label: Text("Awareness Summary").font(.caption2)) {
                                        Text(sum).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                if let hist = ctx.awarenessHistory, !hist.isEmpty {
                                    GroupBox(label: Text("History Overview").font(.caption2)) {
                                        Text(hist).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                if !ctx.snippets.isEmpty {
                                    GroupBox(label: Text("Memory Snippets").font(.caption2)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(ctx.snippets.enumerated()), id: \.offset) { _, s in
                                                Text("• \(s)")
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                                if !ctx.baselines.isEmpty {
                                    GroupBox(label: Text("Baselines").font(.caption2)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(ctx.baselines.enumerated()), id: \.offset) { _, s in
                                                Text("• \(s)")
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                                if !ctx.drifts.isEmpty {
                                    GroupBox(label: Text("Recent Drift").font(.caption2)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(ctx.drifts.enumerated()), id: \.offset) { _, s in
                                                Text("• \(s)")
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                                if !ctx.patterns.isEmpty {
                                    GroupBox(label: Text("Patterns").font(.caption2)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(ctx.patterns.enumerated()), id: \.offset) { _, s in
                                                Text("• \(s)")
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            } else {
                                Text("No injected context yet. Send a message to see what’s used.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 220)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

                // Composer
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        TextEditor(text: $input)
                            .focused($inputFocused)
                            .font(.body)
                            .frame(minHeight: 160)
                            .padding(6)
                    }
                    .frame(minHeight: 180)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                    HStack {
                        Spacer()
                        Button(controller.state == .streaming ? "Streaming" : "Send") {
                            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { inputFocused = true; return }
                            controller.send(trimmed)
                            input = ""
                            inputFocused = true
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(controller.state == .streaming)
                    }
                }
            }
            .padding(14)
        }
        .onAppear {
            inputFocused = true
            strictOn = controller.config.strictMemoryMode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .onTapGesture { inputFocused = true }
#else
        // iOS / others: fallback to simple stacked layout
        VStack(spacing: 12) {
            Text("MemChat").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.turns, id: \.id) { t in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You").font(.caption).foregroundStyle(.secondary)
                            Text(t.prompt)
                            Text("Assistant").font(.caption).foregroundStyle(.secondary)
                            Text(t.answer)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !controller.streamingText.isEmpty {
                        Text(controller.streamingText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Message").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $input)
                    .focused($inputFocused)
                    .font(.body)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                HStack { Spacer(); Button("Send") { let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { inputFocused = true; return }; controller.send(trimmed); input = ""; inputFocused = true } }
            }
        }
        .padding(12)
        .onAppear { inputFocused = true }
#endif
    }
}
