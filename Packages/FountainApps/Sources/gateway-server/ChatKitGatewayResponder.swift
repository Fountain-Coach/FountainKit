import Foundation
import ChatKitGatewayPlugin
import LLMGatewayPlugin

struct ChatKitGatewayResponder: ChatResponder {
    private let handlers: LLMGatewayPlugin.Handlers
    private let defaultModel: String

    init(plugin: LLMGatewayPlugin = LLMGatewayPlugin(),
         defaultModel: String? = nil) {
        self.handlers = plugin.router.handlers
        self.defaultModel = defaultModel
            ?? ProcessInfo.processInfo.environment["CHATKIT_DEFAULT_MODEL"]
            ?? "gpt-4o-mini"
    }

    func respond(session: ChatKitSessionStore.StoredSession,
                 request: ChatKitMessageRequest,
                 preferStreaming: Bool) async throws -> ChatResponderResult {
        let modelHint = request.metadata?["model"] ?? session.metadata["model"]
        let model = (modelHint?.isEmpty == false) ? modelHint! : defaultModel
        let llmMessages = request.messages.map { MessageObject(role: $0.role, content: $0.content) }
        let chatRequest = ChatRequest(model: model, messages: llmMessages)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(chatRequest)

        let path = preferStreaming ? "/chat?stream=1" : "/chat"
        let httpRequest = HTTPRequest(
            method: "POST",
            path: path,
            headers: ["Content-Type": "application/json"],
            body: body
        )

        let response = try await handlers.chatWithObjective(httpRequest, body: chatRequest)
        guard (200...299).contains(response.status) else {
            throw ChatKitGatewayError.llmFailure(status: response.status)
        }
        return try decodeResponse(data: response.body,
                                  contentType: response.headers["Content-Type"],
                                  preferStreaming: preferStreaming)
    }

    private func decodeResponse(data: Data,
                                contentType: String?,
                                preferStreaming: Bool) throws -> ChatResponderResult {
        if preferStreaming, let contentType, contentType.contains("text/event-stream") {
            return try decodeSSEPayload(data)
        }
        return try decodeJSONPayload(data)
    }

    private func decodeJSONPayload(_ data: Data) throws -> ChatResponderResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatKitGatewayError.invalidResponse("non JSON body")
        }

        guard let answer = extractAnswer(from: object) else {
            throw ChatKitGatewayError.invalidResponse("missing answer")
        }

        let provider = object["provider"] as? String
        let model = object["model"] as? String
        let usage = extractUsage(from: object["usage"])

        return ChatResponderResult(answer: answer,
                                   provider: provider,
                                   model: model,
                                   usage: usage,
                                   streamEvents: nil)
    }

    private func decodeSSEPayload(_ data: Data) throws -> ChatResponderResult {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ChatKitGatewayError.invalidResponse("invalid SSE payload")
        }

        var answerFragments: [String] = []
        var provider: String?
        var model: String?
        var usage: [String: Double]?
        var events: [ChatKitStreamEventEnvelope] = []

        for block in text.components(separatedBy: "\n\n") where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var eventName: String?
            var eventId: String?
            var payloads: [String] = []
            for rawLine in block.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("event:") {
                    eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("id:") {
                    eventId = String(line.dropFirst("id:".count)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                    payloads.append(payload)
                }
            }

            for payload in payloads {
                guard payload != "[DONE]", let jsonData = payload.data(using: .utf8) else { continue }
                guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

                if let delta = (object["delta"] as? [String: Any])?["content"] as? String, !delta.isEmpty {
                    answerFragments.append(delta)
                    events.append(ChatKitStreamEventEnvelope(id: eventId,
                                                             event: eventName ?? "delta",
                                                             delta: ChatKitStreamDelta(content: delta),
                                                             answer: nil,
                                                             done: nil,
                                                             thread_id: nil,
                                                             response_id: nil,
                                                             created_at: nil,
                                                             metadata: nil))
                }

                if let finalAnswer = object["answer"] as? String, !finalAnswer.isEmpty {
                    answerFragments.append(finalAnswer)
                }

                if provider == nil { provider = object["provider"] as? String }
                if model == nil { model = object["model"] as? String }
                if usage == nil, let rawUsage = object["usage"] {
                    usage = extractUsage(from: rawUsage)
                }
            }
        }

        let answer = answerFragments.joined()
        guard !answer.isEmpty else {
            throw ChatKitGatewayError.invalidResponse("empty SSE answer")
        }

        let uniqueEvents = events.deduplicating()

        return ChatResponderResult(answer: answer,
                                   provider: provider,
                                   model: model,
                                   usage: usage,
                                   streamEvents: uniqueEvents)
    }

    private func extractAnswer(from object: [String: Any]) -> String? {
        if let answer = object["answer"] as? String, !answer.isEmpty { return answer }
        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.isEmpty {
            return content
        }
        return nil
    }

    private func extractUsage(from raw: Any?) -> [String: Double]? {
        guard let dict = raw as? [String: Any] else { return nil }
        var usage: [String: Double] = [:]
        for (key, value) in dict {
            if let number = value as? NSNumber {
                usage[key] = number.doubleValue
            } else if let str = value as? String, let dbl = Double(str) {
                usage[key] = dbl
            }
        }
        return usage.isEmpty ? nil : usage
    }
}

private extension Array where Element == ChatKitStreamEventEnvelope {
    func deduplicating() -> [ChatKitStreamEventEnvelope] {
        var seen: Set<String> = []
        var output: [ChatKitStreamEventEnvelope] = []
        output.reserveCapacity(count)
        let encoder = JSONEncoder()
        for event in self {
            if let data = try? encoder.encode(event),
               let signature = String(data: data, encoding: .utf8),
               !seen.insert(signature).inserted {
                continue
            }
            output.append(event)
        }
        return output
    }
}
