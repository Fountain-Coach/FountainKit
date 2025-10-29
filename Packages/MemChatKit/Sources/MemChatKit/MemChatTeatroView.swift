import SwiftUI
import Combine
import Teatro

/// Cross-platform MemChat surface built with Teatro GUI primitives.
/// Embedding hosts can integrate the streaming token inspector while
/// reusing the existing `MemChatController` orchestration layer.
public struct MemChatTeatroView: View {
    @StateObject private var controller: MemChatController
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool
    @State private var pendingSendStartedAt: Date? = nil
    @State private var lastRoundTripMs: Int = 0

    public init(configuration: MemChatConfiguration) {
        _controller = StateObject(wrappedValue: MemChatController(config: configuration))
    }

    public init(controller: MemChatController) {
        _controller = StateObject(wrappedValue: controller)
    }

    public var body: some View {
        VStack(spacing: 16) {
            header
            StreamStatusView(
                connected: isConnected,
                acks: controller.turns.count,
                nacks: controller.lastError == nil ? 0 : 1,
                rtt: Double(lastRoundTripMs),
                window: max(controller.streamingTokens.count, 1),
                loss: controller.lastError == nil ? 0 : 100
            )
            .accessibilityLabel("Stream status")

            if let err = controller.lastError, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(err).font(.caption)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            mainContent
            composer
        }
        .padding(16)
        .onAppear {
            focusInput()
        }
        .onReceive(controller.$turns) { _ in
            if let startedAt = pendingSendStartedAt {
                lastRoundTripMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                pendingSendStartedAt = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MemChat Teatro").font(.title3).bold()
                if let title = controller.corpusTitle { Text(title).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle(isOn: Binding(get: { controller.config.strictMemoryMode }, set: { controller.setStrictMemoryMode($0) })) {
                Text("Strict")
            }
            .toggleStyle(.switch)
            .help("Strict Memory Mode: answer strictly from stored site memory with citations")
            Button("Reset") { Task { _ = await controller.resetMemoryCorpus() } }
                .disabled(controller.state == .streaming)
            Text(providerLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("New Chat") { controller.newChat() }
                .disabled(controller.state == .streaming)
        }
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if controller.config.showSemanticPanel, let panel = controller.semanticPanel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Semantic Panel")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    }
                    if let report = controller.calculusReport {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Calculus Report")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Baseline: \(report.baselineSource.rawValue)")
                            Text("Drift: \(report.driftSource.rawValue)")
                            Text("Patterns: \(report.patternsSource.rawValue)")
                            Text("Reflection: \(report.reflectionSource.rawValue)")
                            Text("Evidence: \(report.evidenceCount) • Baseline chars: \(report.baselineLength)")
                            Text("Drift lines: \(report.driftLines) • Patterns: \(report.patternsLines)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    }
                    // Evidence: What we learned (recent cited segments)
                    if !controller.recentEvidence.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What we learned")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(controller.recentEvidence.prefix(8).enumerated()), id: \.offset) { _, e in
                                Text("• \(e.text) — \(e.title)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    }
                    ForEach(controller.turns, id: \.id) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("You")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(turn.prompt)
                            Divider()
                            Text("Assistant")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(turn.answer)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                    if !controller.streamingText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Streaming…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(controller.streamingText)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.4))
                        )
                    }
                    if !controller.memoryTrail.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Memory Trail")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(controller.memoryTrail.suffix(4), id: \.self) { line in
                                Text(line).font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TokenStreamView(tokens: controller.streamingTokens, showBeatGrid: true)
                .frame(minWidth: 220, minHeight: 180)
                .accessibilityLabel("Token stream")
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $input)
                .focused($inputFocused)
                .font(.body)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25))
                )
            HStack {
                Spacer()
                Button(controller.state == .streaming ? "Streaming" : "Send") {
                    sendPrompt()
                }
                .disabled(controller.state == .streaming)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private var providerLabel: String {
        controller.providerLabel.isEmpty ? "" : "provider: \(controller.providerLabel)"
    }

    private var isConnected: Bool {
        switch controller.state {
        case .failed:
            return false
        default:
            return true
        }
    }

    private func sendPrompt() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            focusInput()
            return
        }
        pendingSendStartedAt = Date()
        controller.send(trimmed)
        input = ""
        focusInput()
    }

    private func focusInput() {
        DispatchQueue.main.async {
            inputFocused = true
        }
    }
}
