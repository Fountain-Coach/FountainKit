import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
// Intentionally avoid PlannerAPI dependency to keep build surface small.

@main
struct EngraverDirectCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            print("Usage: engraver-direct <chat|plan> <text>")
            exit(2)
        }
        switch cmd {
        case "chat":
            let prompt = args.dropFirst().joined(separator: " ")
            if prompt.isEmpty { print("Provide a prompt"); exit(2) }
            do { try await chat(prompt: prompt) } catch { fputs("chat error: \(error)\n", stderr); exit(1) }
        case "plan":
            let objective = args.dropFirst().joined(separator: " ")
            if objective.isEmpty { print("Provide an objective"); exit(2) }
            do { try await plan(objective: objective) } catch { fputs("plan error: \(error)\n", stderr); exit(1) }
        default:
            print("Unknown command: \(cmd)")
            exit(2)
        }
    }

    static func chat(prompt: String) async throws {
        // Prefer LocalAgent endpoint; fallback to Ollama OpenAI-compatible endpoint if not set
        let llmURL = URL(string: ProcessInfo.processInfo.environment["LLM_URL"] ?? "http://127.0.0.1:8080/chat")!
        var req = URLRequest(url: llmURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "local",
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "error"
            throw NSError(domain: "engraver-direct", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        // Extract answer from OpenAI-like payload
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = obj["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            print(content)
        } else {
            // Print raw JSON on fallback
            print(String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func plan(objective: String) async throws {
        let base = URL(string: ProcessInfo.processInfo.environment["PLANNER_URL"] ?? "http://127.0.0.1:8003")!
        var req = URLRequest(url: base.appendingPathComponent("/planner/reason"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["objective": objective]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "error"
            throw NSError(domain: "engraver-direct", code: (resp as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print(String(data: try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8) ?? "")
        } else {
            print(String(data: data, encoding: .utf8) ?? "")
        }
    }
}
