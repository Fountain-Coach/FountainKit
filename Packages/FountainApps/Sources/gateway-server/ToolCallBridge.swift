import Foundation
import ChatKitGatewayPlugin

/// Utility that converts tool call models into ChatKit stream events so
/// clients can react to function execution during streaming responses.
struct ToolCallBridge {
    /// Creates stream events for the supplied tool calls. Each call produces a
    /// `tool_call` event containing the invocation metadata. When the upstream
    /// model also returns a result payload we emit a follow-up `tool_result`
    /// event so ChatKit consumers can surface outputs immediately.
    ///
    /// - Parameter toolCalls: Tool call descriptors returned by the LLM.
    /// - Returns: ChatKit stream events that describe the tool lifecycle.
    static func events(for toolCalls: [ChatKitToolCall]) -> [ChatKitStreamEventEnvelope] {
        guard !toolCalls.isEmpty else { return [] }

        var events: [ChatKitStreamEventEnvelope] = []
        events.reserveCapacity(toolCalls.count * 2)

        for (index, call) in toolCalls.enumerated() {
            let baseMetadata = makeMetadata(for: call, index: index)
            events.append(
                ChatKitStreamEventEnvelope(
                    id: "\(call.id)#call\(index)",
                    event: "tool_call",
                    delta: nil,
                    answer: nil,
                    done: nil,
                    thread_id: nil,
                    response_id: nil,
                    created_at: nil,
                    metadata: baseMetadata
                )
            )

            if let result = call.result, !result.isEmpty {
                var resultMetadata = baseMetadata
                resultMetadata["tool.result"] = result
                events.append(
                    ChatKitStreamEventEnvelope(
                        id: "\(call.id)#result\(index)",
                        event: "tool_result",
                        delta: nil,
                        answer: nil,
                        done: nil,
                        thread_id: nil,
                        response_id: nil,
                        created_at: nil,
                        metadata: resultMetadata
                    )
                )
            }
        }

        return events
    }

    private static func makeMetadata(for call: ChatKitToolCall, index: Int) -> [String: String] {
        var metadata: [String: String] = [
            "tool.id": call.id,
            "tool.name": call.name,
            "tool.arguments": call.arguments,
            "tool.index": String(index)
        ]
        if let status = call.status, !status.isEmpty {
            metadata["tool.status"] = status
        }
        return metadata
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
