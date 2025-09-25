import Foundation
import FountainRuntime
import LLMGatewayPlugin

@main
struct Demo {
    static func main() async {
        let router = LLMGatewayPlugin.Router()
        let reqBody = LLMGatewayPlugin.ChatRequest(
            model: "local-mock-1",
            messages: [
                .init(role: "user", content: "call schedule_meeting with {\"title\":\"Team sync\",\"time\":\"2025-01-01 10:00\"}")
            ],
            functions: [
                .init(name: "schedule_meeting", description: "Schedule a meeting")
            ],
            function_call: .auto
        )
        do {
            let data = try JSONEncoder().encode(reqBody)
            let http = HTTPRequest(method: "POST", path: "/chat", body: data)
            if let resp = try await router.route(http) {
                print(String(data: resp.body, encoding: .utf8) ?? "<binary>")
            } else {
                fputs("no route\n", stderr)
                exit(2)
            }
        } catch {
            fputs("demo error: \(error)\n", stderr)
            exit(1)
        }
    }
}

