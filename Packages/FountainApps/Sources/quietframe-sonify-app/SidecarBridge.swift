import Foundation
import QuietFrameKit

@MainActor final class SidecarBridge {
    static let shared = SidecarBridge()
    let client: QuietFrameSidecarClient
    private init() {
        // Target ourselves by display name so vendor ops can reach the local instrument if needed.
        let cfg = QuietFrameSidecarClient.Config(targetDisplayName: "QuietFrame")
        self.client = QuietFrameSidecarClient(config: cfg)
        // We don't need polling in this app yet; uncomment if inbound events are desired.
        // Task { await client.startPolling(pollIntervalMs: 250) }
    }
    func sendVendor(topic: String, data: [String: Any] = [:]) {
        Task { await client.sendVendor(topic: topic, data: data) }
    }

    func sendNoteEvent(_ event: [String: Any]) {
        let base = URL(string: ProcessInfo.processInfo.environment["MVK_RUNTIME_URL"] ?? "http://127.0.0.1:7777")!
        var req = URLRequest(url: base.appendingPathComponent("/v1/midi/notes/ingest"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: event)
        Task { _ = try? await URLSession.shared.data(for: req) }
    }
}
