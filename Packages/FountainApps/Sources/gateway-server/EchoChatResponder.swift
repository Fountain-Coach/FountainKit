import Foundation
import FountainRuntime
import ChatKitGatewayPlugin

/// Simple development responder that echoes the last user message content.
/// Useful for local UI bring-up without a running LLM pipeline.
struct EchoChatResponder: ChatResponder {
    func respond(session: ChatKitSessionStore.StoredSession,
                 request: ChatKitMessageRequest,
                 preferStreaming: Bool) async throws -> ChatResponderResult {
        // Find the last user message content
        let userText = request.messages.last(where: { $0.role.lowercased() == "user" })?.content ?? ""
        return ChatResponderResult(
            answer: userText,
            provider: "echo",
            model: session.metadata["model"] ?? "echo-dev",
            usage: ["prompt_tokens": Double(userText.count)],
            streamEvents: nil,
            toolCalls: nil
        )
    }
}

