import Foundation
// Avoid importing MetalViewKit to keep the runner link-safe
import FountainRuntime
import MetalViewKitRuntimeServerKit

@main
struct Main {
    static func main() async {
        do {
            let result = try await run()
            print(result)
            exit(0)
        } catch {
            fputs("mvk-runtime-tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws -> String {
        // Start runtime server on ephemeral port
        let fallback = HTTPKernel { req in
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/metalviewkit-runtime-server/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            }
            return HTTPResponse(status: 404)
        }
        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        try MetalViewKitRuntimeServer.register(on: transport)
        let server = NIOHTTPServer(kernel: transport.asKernel())
        let port = try await server.start(port: 0)

        // Health
        let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
        let (hdata, hresp) = try await URLSession.shared.data(from: healthURL)
        guard (hresp as? HTTPURLResponse)?.statusCode == 200,
              let hobj = try? JSONSerialization.jsonObject(with: hdata) as? [String: Any],
              hobj["status"] as? String == "ok" else {
            throw NSError(domain: "mvk-runtime-tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "health failed"])
        }

        // Inject a CC event by displayName
        let w0: UInt32 = (0x4 << 28) | (0 << 24) | (0xB << 20) | (0 << 16) | (1 << 8)
        let w1: UInt32 = 0x7F
        let injectURL = URL(string: "http://127.0.0.1:\(port)/v1/midi/events")!
        let body: [String: Any] = ["events": [["tNs": "0", "packet": ["w0": Int(w0), "w1": Int(w1)]]]]
        var req = URLRequest(url: injectURL)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, iresp) = try await URLSession.shared.data(for: req)
        guard (iresp as? HTTPURLResponse)?.statusCode == 202 else { throw NSError(domain: "mvk-runtime-tests", code: 2, userInfo: [NSLocalizedDescriptionKey: "inject failed"]) }

        // Read back via server buffer (does not require in-process loopback)
        let (edata, eresp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/midi/vendor?limit=1")!)
        guard (eresp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: edata) as? [String: Any],
              let events = obj["events"] as? [[String: Any]],
              let pkt = events.first?["packet"] as? [String: Any],
              (pkt["w0"] as? Int) == Int(w0), (pkt["w1"] as? Int) == Int(w1) else {
            throw NSError(domain: "mvk-runtime-tests", code: 3, userInfo: [NSLocalizedDescriptionKey: "no UMP echoed"])
        }

        // Summary
        let summary: [String: Any] = [
            "ok": true,
            "port": port,
            "echoedUMP": [String(format: "0x%08X", w0), String(format: "0x%08X", w1)]
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{\"ok\":true}"
    }
}
