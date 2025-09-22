import Foundation
import Crypto

/// Utility for signing DNS zone data using Ed25519.
public struct DNSSECSigner: @unchecked Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey

    /// Creates a signer with the provided private key.
    public init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    /// Produces an Ed25519 signature for the given zone string.
    /// - Parameter zone: YAML string representing the zone file.
    /// - Returns: Raw signature bytes.
    public func sign(zone: String) throws -> Data {
        try privateKey.signature(for: Data(zone.utf8))
    }

    /// Verifies a signature against the zone string.
    /// - Parameters:
    ///   - zone: YAML zone string.
    ///   - signature: Signature bytes to verify.
    /// - Returns: True if the signature is valid.
    public func verify(zone: String, signature: Data) -> Bool {
        privateKey.publicKey.isValidSignature(signature, for: Data(zone.utf8))
    }

    /// Public key corresponding to the private key.
    public var publicKey: Curve25519.Signing.PublicKey { privateKey.publicKey }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

