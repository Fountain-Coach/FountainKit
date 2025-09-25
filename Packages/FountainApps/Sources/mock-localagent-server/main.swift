import Foundation
import FountainRuntime

@main
struct MockLocalAgentServer {
    static func main() async {
        let kernel = HTTPKernel { req in
            let pathOnly = req.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? req.path
            switch (req.method, pathOnly) {
            case ("GET", "/health"):
                let data = try JSONSerialization.data(withJSONObject: ["status": "ok"]) 
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            case ("POST", "/chat"):
                // naive function_call response for tests
                let resp: [String: Any] = [
                    "id": UUID().uuidString,
                    "object": "chat.completion",
                    "choices": [[
                        "message": [
                            "role": "assistant",
                            "content": NSNull(),
                            "function_call": [
                                "name": "schedule_meeting",
                                "arguments": "{\"title\":\"Team sync\",\"time\":\"2025-01-01 10:00\"}"
                            ]
                        ]
                    ]]
                ]
                let data = try JSONSerialization.data(withJSONObject: resp)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            default:
                return HTTPResponse(status: 404)
            }
        }
        let server = NIOHTTPServer(kernel: kernel)
        do {
            let port = Int(ProcessInfo.processInfo.environment["LOCAL_AGENT_PORT"] ?? "8080") ?? 8080
            _ = try await server.start(port: port)
            print("mock-localagent listening on :\(port)")
        } catch {
            FileHandle.standardError.write(Data("[mock-localagent] Failed to start: \(error)\n".utf8))
        }
        dispatchMain()
    }
}

