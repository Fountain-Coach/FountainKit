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
}

