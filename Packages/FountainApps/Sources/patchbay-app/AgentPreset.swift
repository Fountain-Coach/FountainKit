import Foundation

// Minimal Agent preset format so artists can flip between canvas and agent control.
// This is intentionally simple and app-local (not part of the service spec).
// It records the PatchBay server baseURL, the current GraphDoc, and a list of
// OpenAPI operationIds that the agent may call.

struct AgentPreset: Codable {
    struct Agent: Codable {
        struct Tool: Codable { let name: String; let operationId: String }
        let name: String
        let tools: [Tool]
        let scene: Scene
        let notes: String?
    }
    struct Scene: Codable { let graph: Components.Schemas.GraphDoc }
    struct Server: Codable { let baseURL: String }

    let version: Int
    let agent: Agent
    let server: Server
}

extension AgentPreset {
    static func build(name: String = "PatchBay Scene",
                      baseURL: URL,
                      graph: Components.Schemas.GraphDoc,
                      notes: String? = nil) -> AgentPreset {
        let tools: [AgentPreset.Agent.Tool] = [
            .init(name: "List Instruments", operationId: "listInstruments"),
            .init(name: "Suggest Links", operationId: "suggestLinks"),
            .init(name: "Create Link", operationId: "createLink"),
            .init(name: "List Links", operationId: "listLinks"),
            .init(name: "Delete Link", operationId: "deleteLink"),
            .init(name: "List Stored Graphs", operationId: "listStoredGraphs"),
            .init(name: "Get Stored Graph", operationId: "getStoredGraph"),
            .init(name: "Put Stored Graph", operationId: "putStoredGraph"),
            .init(name: "Create Corpus Snapshot", operationId: "createCorpusSnapshot")
        ]
        return AgentPreset(
            version: 1,
            agent: .init(name: name,
                         tools: tools,
                         scene: .init(graph: graph),
                         notes: notes),
            server: .init(baseURL: baseURL.absoluteString)
        )
    }
}

