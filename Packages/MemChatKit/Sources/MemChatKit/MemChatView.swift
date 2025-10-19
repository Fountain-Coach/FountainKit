import SwiftUI
import FountainAIKit

/// Drop-in SwiftUI view for MemChat.
/// Host apps can either use this directly or compose their own view while
/// holding a reference to `MemChatController`.
public struct MemChatView: View {
    @StateObject private var controller: MemChatController
    @State private var input: String = ""

    public init(configuration: MemChatConfiguration) {
        _controller = StateObject(wrappedValue: MemChatController(config: configuration))
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
            HStack {
                TextField("Type a message…", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    controller.send(trimmed)
                    input = ""
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(controller.state == .streaming)
            }
        }
        .padding(12)
    }
}

