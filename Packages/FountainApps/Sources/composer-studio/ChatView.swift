import SwiftUI

struct ChatView: View {
    @Binding var messages: [ChatMessage]
    var onSend: (String) -> Void
    @State private var draft: String = ""
    @Namespace private var bubbleNS

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in
                            bubble(for: msg)
                                .id(msg.id)
                                .transition(msg.role == .assistant ? .move(edge: .trailing).combined(with: .opacity) : .move(edge: .leading).combined(with: .opacity))
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: messages)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            HStack(spacing: 8) {
                TextField("Say what should happen…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        onSend(text)
    }

    @ViewBuilder
    private func bubble(for msg: ChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if msg.role == .assistant { Spacer(minLength: 24) }
            Text(msg.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(msg.role == .assistant ? .white : .primary)
                .background(msg.role == .assistant ? Color.accentColor : Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .matchedGeometryEffect(id: msg.id, in: bubbleNS, isSource: true)
            if msg.role == .user { Spacer(minLength: 24) }
        }
    }
}

