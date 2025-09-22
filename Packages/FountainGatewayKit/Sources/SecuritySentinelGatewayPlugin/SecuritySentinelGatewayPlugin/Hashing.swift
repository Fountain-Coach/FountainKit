import Foundation
/// Lightweight hashing helper avoiding external crypto dependencies.
enum Hashing {
    /// Returns a deterministic hex string derived from the input.
    ///
    /// This is **not** cryptographically secure; it exists solely to avoid
    /// depending on additional crypto packages while still providing a stable
    /// obfuscation of logged summaries.
    static func sha256Hex(_ input: String) -> String {
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
