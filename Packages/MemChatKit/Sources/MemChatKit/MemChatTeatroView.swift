import SwiftUI
import Combine
import TeatroGUI

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
                rtt: lastRoundTripMs,
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
