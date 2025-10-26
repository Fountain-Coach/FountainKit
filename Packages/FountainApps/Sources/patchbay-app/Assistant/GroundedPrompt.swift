import Foundation
import LLMGatewayAPI

enum GroundedPromptBuilder {
    static func systemPrompt() -> String {
        """
        You are the PatchBay Studio assistant. Be concise and accurate.
        You can answer questions about the current scene (nodes/links) and the wider corpus.
        When a user asks to make changes, return a function_call with name "openapi_action"
        whose arguments is a JSON object or array describing one or more OpenAPI actions.

        Action schema (OpenAPIAction):
        {
          "service": "patchbay-service",
          "operationId": "createLink" | "deleteLink",
          "pathParams": { "id": "..." },  // optional for deleteLink
          "body": { ... }                    // required for createLink; payload matches the service spec
        }

        If you only need to answer a question, do not return a function_call.
        """
    }

    static func sceneSummary(nodes: [PBNode], edges: [PBEdge]) -> String {
        var s: [String] = []
        s.append("Scene: \(nodes.count) nodes; \(edges.count) links.")
        if !nodes.isEmpty {
            s.append("Nodes:")
            for n in nodes { s.append("- \(n.id): \(n.title ?? n.id) ports=\(n.ports.count)") }
        }
        if !edges.isEmpty {
            s.append("Links:")
            for e in edges { s.append("- \(e.from) → \(e.to)") }
        }
        return s.joined(separator: "\n")
    }

    static func makeChatRequest(model: String, userQuestion: String, nodes: [PBNode], edges: [PBEdge]) -> ChatRequest {
        let sys = systemPrompt()
        let summary = sceneSummary(nodes: nodes, edges: edges)
        let content = """
        Current scene summary:\n\n\(summary)\n\nUser Question: \n\(userQuestion)
        """
        return ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: sys),
                .init(role: "user", content: content)
            ],
            functions: nil,
            function_call: nil
        )
    }
}
