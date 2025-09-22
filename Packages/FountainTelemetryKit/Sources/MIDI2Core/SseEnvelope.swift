import Foundation

public struct SseEnvelope: Codable, Equatable, Sendable {
    public struct Fragment: Codable, Equatable, Sendable {
        public let i: Int
        public let n: Int

        public init(i: Int, n: Int) {
            self.i = i
            self.n = n
        }
    }

    public let v: Int
    public let ev: String
    public let id: String?
    public let ct: String?
    public let seq: UInt64
    public let frag: Fragment?
    public let ts: Double?
    public let data: String?

    public init(
        v: Int = 1,
        ev: String,
        id: String? = nil,
        ct: String? = nil,
        seq: UInt64,
        frag: Fragment? = nil,
        ts: Double? = nil,
        data: String? = nil
    ) {
        self.v = v
        self.ev = ev
        self.id = id
        self.ct = ct
        self.seq = seq
        self.frag = frag
        self.ts = ts
        self.data = data
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
