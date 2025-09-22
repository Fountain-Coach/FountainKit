import Foundation

public final class LoopbackTransport: MIDITransport {
    public var onReceiveUMP: (([UInt32]) -> Void)?

    public init() {}

    public func open() throws {}

    public func close() throws {}

    public func send(umpWords: [UInt32]) throws {
        onReceiveUMP?(umpWords)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
