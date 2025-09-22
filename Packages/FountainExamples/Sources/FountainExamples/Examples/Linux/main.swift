import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TeatroRenderAPI

@main
struct HelloFountainAITeatro {
    static func main() async throws {
        let url = URL(string: "http://127.0.0.1:8006/v1/health")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = obj?["status"] as? String ?? "unknown"
        let message = "Hello FountainAI World — \(status)"
        let input = SimpleScriptInput(fountainText: message)
        let result = try TeatroRenderer.renderScript(input)
        if let svgData = result.svg, let svg = String(data: svgData, encoding: .utf8) {
            print(svg)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
