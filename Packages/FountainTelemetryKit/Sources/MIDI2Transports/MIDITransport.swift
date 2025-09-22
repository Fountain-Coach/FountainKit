import Foundation

public protocol MIDITransport {
    func open() throws
    func close() throws
    func send(umpWords: [UInt32]) throws
    var onReceiveUMP: (([UInt32]) -> Void)? { get set }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
