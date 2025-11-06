import Foundation
import MetalViewKit

/// MVKBridge offers a tiny shim for tests to forward runtime UMP words
/// to a running MetalViewKit instrument by display name.
///
/// In ROBOT_ONLY mode, the default transport is Loopback; otherwise CoreMIDI.
public enum MVKBridge {
    /// Sends UMP words to the first MVK instrument whose display name contains `displayNameSubstring`.
    /// Returns true when a matching instrument was found and accepted the words.
    @discardableResult
    public static func sendUMP(words: [UInt32], toDisplayNameContaining displayNameSubstring: String) -> Bool {
        LoopbackMetalInstrumentTransport.shared.send(words: words, toDisplayName: displayNameSubstring)
    }

    /// Sends a batch of UMP words arrays to a target resolved from env or a provided substring.
    /// If `targetDisplayNameSubstring` is nil, falls back to `MVK_BRIDGE_TARGET` env, else "Canvas".
    @discardableResult
    public static func sendBatch(_ batch: [[UInt32]], targetDisplayNameSubstring: String? = nil) -> Int {
        let fallback = ProcessInfo.processInfo.environment["MVK_BRIDGE_TARGET"] ?? "Canvas"
        let target = (targetDisplayNameSubstring?.isEmpty == false) ? targetDisplayNameSubstring! : fallback
        var delivered = 0
        for words in batch {
            if LoopbackMetalInstrumentTransport.shared.send(words: words, toDisplayName: target) { delivered += 1 }
        }
        return delivered
    }
}
