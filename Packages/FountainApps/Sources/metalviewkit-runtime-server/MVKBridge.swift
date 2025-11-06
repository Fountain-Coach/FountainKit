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
}

