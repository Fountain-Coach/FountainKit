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
    @FocusState private var inputFocused: Bool

    public init(configuration: MemChatConfiguration) {
        _controller = StateObject(wrappedValue: MemChatController(config: configuration))
    }

    public init(controller: MemChatController) {
        _controller = StateObject(wrappedValue: controller)
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("MemChat")
                    .font(.title3).bold()
                Spacer()
                Text(controller.chatCorpusId)
                    .font(.caption).foregroundStyle(.secondary)
                Button("New Chat") { controller.newChat() }
            }
            .padding(.top, 4)

            if let err = controller.lastError, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(err).font(.caption)
                    Spacer()
                }
                .padding(8)
                .background(Color.yellow.opacity(0.12))
                .cornerRadius(6)
            }

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
                HStack {
                    Spacer()
                    Button("Send") {
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
        .padding(12)
        .onAppear {
            inputFocused = true
            #if canImport(AppKit)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            #endif
        }
        .onTapGesture { inputFocused = true }
    }
}
