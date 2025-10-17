import Foundation
import FountainAICore
import LLMGatewayAPI

// Bridge GatewayChatClient to core chat contracts so app code can depend on FountainCore/AIGit.
extension GatewayChatClient: CoreChatStreaming {
    public func stream(request core: CoreChatRequest, preferStreaming: Bool) -> AsyncThrowingStream<CoreChatChunk, Error> {
        let messages = core.messages.map { LLMGatewayAPI.ChatMessage(role: $0.role.rawValue, content: $0.content) }
        let mapped = LLMGatewayAPI.ChatRequest(model: core.model, messages: messages)
        let base = self.stream(request: mapped, preferStreaming: preferStreaming)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in base {
                        let mapped = CoreChatChunk(
                            text: chunk.text,
                            isFinal: chunk.isFinal,
                            response: chunk.response.map { CoreChatResponse(answer: $0.answer, provider: $0.provider, model: $0.model) }
                        )
                        continuation.yield(mapped)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func complete(request core: CoreChatRequest) async throws -> CoreChatResponse {
        let messages = core.messages.map { LLMGatewayAPI.ChatMessage(role: $0.role.rawValue, content: $0.content) }
        let mapped = LLMGatewayAPI.ChatRequest(model: core.model, messages: messages)
        let resp = try await self.complete(request: mapped)
        return CoreChatResponse(answer: resp.answer, provider: resp.provider, model: resp.model)
    }
}

