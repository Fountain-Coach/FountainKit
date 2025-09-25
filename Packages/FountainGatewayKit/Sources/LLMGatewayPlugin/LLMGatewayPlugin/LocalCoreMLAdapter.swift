import Foundation

/// Extremely simple in-process LLM adapter. Keeps things minimal:
/// - If CoreML is available and a model path is provided via env `LLM_COREML_MODEL`,
///   this is where you would load and run it. For now, we return a placeholder
///   to keep the integration simple.
/// - Otherwise, returns a deterministic mock response. When `functions` are
///   present and the user hints a call like "call <name> with {json}", it emits
///   an OpenAI-style function_call response. Otherwise it echoes text.
struct LocalCoreMLAdapter: Sendable {
    private let modelPath: String?
    init(modelPath: String? = nil) { self.modelPath = modelPath }
    func respond(to req: ChatRequest) throws -> Data {
        // Minimal heuristic for function_call: detect "call <name> with {..}"
        let lastUser = req.messages.last(where: { $0.role.lowercased() == "user" })?.content ?? ""
        if let tools = req.functions, !tools.isEmpty,
           let (name, args) = parseFunctionCallHint(in: lastUser, tools: tools, option: req.function_call) {
            let resp = makeFunctionCallResponse(model: req.model, name: name, arguments: args)
            return try JSONSerialization.data(withJSONObject: resp, options: [])
        }
        // Otherwise plain text reply (optionally mention CoreML model if provided)
        let text: String = {
            if let mh = modelPath, !mh.isEmpty { return "[coreml:\(URL(fileURLWithPath: mh).lastPathComponent)] " + defaultTextReply(for: lastUser, functions: req.functions) }
            return defaultTextReply(for: lastUser, functions: req.functions)
        }()
        let resp = makeTextResponse(model: req.model, text: text)
        return try JSONSerialization.data(withJSONObject: resp, options: [])
    }

    private func parseFunctionCallHint(in text: String,
                                       tools: [FunctionObject],
                                       option: FunctionCall?) -> (String, String)? {
        // Respect explicit request
        if case .named(let fc)? = option { return (fc.name, extractJSONArguments(from: text) ?? "{}") }
        if case .auto? = option, let match = tools.first(where: { tool in
            text.localizedCaseInsensitiveContains("call \(tool.name)") ||
            text.localizedCaseInsensitiveContains("use \(tool.name)") ||
            text.localizedCaseInsensitiveContains("\(tool.name)(") ||
            text.localizedCaseInsensitiveContains("\(tool.name) {") ||
            text.localizedCaseInsensitiveContains("\(tool.name) with")
        }) {
            return (match.name, extractJSONArguments(from: text) ?? "{}")
        }
        return nil
    }

    private func extractJSONArguments(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let candidate = String(text[start...end])
        if let data = candidate.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return candidate
        }
        return nil
    }

    private func defaultTextReply(for lastUser: String, functions: [FunctionObject]?) -> String {
        if let tools = functions, !tools.isEmpty {
            return "No tool call detected. Provide JSON args to call \(tools[0].name)."
        }
        return lastUser.isEmpty ? "Hello!" : "Echo: \(lastUser)"
    }

    private func makeTextResponse(model: String, text: String) -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970)
        let obj: [String: Any] = [
            "id": "chatcmpl-local-\(UUID().uuidString.prefix(8))",
            "object": "chat.completion",
            "created": ts,
            "model": model,
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": text],
                "finish_reason": "stop"
            ]]
        ]
        return obj
    }

    private func makeFunctionCallResponse(model: String, name: String, arguments: String) -> [String: Any] {
        let ts = Int(Date().timeIntervalSince1970)
        let obj: [String: Any] = [
            "id": "chatcmpl-local-\(UUID().uuidString.prefix(8))",
            "object": "chat.completion",
            "created": ts,
            "model": model,
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": NSNull(),
                    "function_call": ["name": name, "arguments": arguments]
                ],
                "finish_reason": "function_call"
            ]]
        ]
        return obj
    }
}
