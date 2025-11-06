import Foundation
import MetalViewKit
import FountainRuntime
import metalviewkit_runtime_server

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

        // Create a loopback MVK instrument
        let iid = UUID().uuidString
        let displayName = "MVKTest#\(iid)"
        // Thread-safe inbox for received UMP frames
        actor UMPInbox {
            private var items: [[UInt32]] = []
            func push(_ words: [UInt32]) { items.append(words) }
            func snapshot() -> [[UInt32]] { items }
        }
        let inbox = UMPInbox()
        let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "MVKTest", instanceId: iid, displayName: displayName)
        let session = try LoopbackMetalInstrumentTransport.shared.makeSession(descriptor: desc) { words in
            // Hop to an async context to avoid mutating from concurrently-executing code
            Task { await inbox.push(words) }
        }
        defer { session.close() }

        // Inject a CC event by displayName
        let w0: UInt32 = (0x4 << 28) | (0 << 24) | (0xB << 20) | (0 << 16) | (1 << 8)
        let w1: UInt32 = 0x7F
        let injectURL = URL(string: "http://127.0.0.1:\(port)/v1/midi/events?targetDisplayName=MVKTest")!
        let body: [String: Any] = ["events": [["tNs": "0", "packet": ["w0": Int(w0), "w1": Int(w1)]]]]
        var req = URLRequest(url: injectURL)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, iresp) = try await URLSession.shared.data(for: req)
        guard (iresp as? HTTPURLResponse)?.statusCode == 202 else { throw NSError(domain: "mvk-runtime-tests", code: 2, userInfo: [NSLocalizedDescriptionKey: "inject failed"]) }

        // Allow delivery
        try await Task.sleep(nanoseconds: 50_000_000)
        let received = await inbox.snapshot()
        guard received.count == 1, received.first == [w0, w1] else {
            throw NSError(domain: "mvk-runtime-tests", code: 3, userInfo: [NSLocalizedDescriptionKey: "no UMP received"])
        }

        // Endpoints list shows live MVK
        let (edata, eresp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/midi/endpoints")!)
        guard (eresp as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: edata) as? [[String: Any]],
              arr.contains(where: { ($0["id"] as? String) == iid || ((($0["value2"] as? [String: Any])?["id"] as? String) == iid) }) else {
            throw NSError(domain: "mvk-runtime-tests", code: 4, userInfo: [NSLocalizedDescriptionKey: "endpoints missing live MVK"])
        }

        // Summary
        let summary: [String: Any] = [
            "ok": true,
            "port": port,
            "target": ["displayName": displayName, "instanceId": iid],
            "receivedUMP": received.first!.map { String(format: "0x%08X", $0) }
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{\"ok\":true}"
    }
}
