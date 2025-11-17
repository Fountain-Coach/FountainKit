import Foundation

// CoreMIDI is prohibited in Swift 6. Provide a safe stub delegating to loopback.
public final class CoreMIDITransport: MIDITransport {
    public var onReceiveUMP: (([UInt32]) -> Void)?
    private let loop = LoopbackTransport()
    public init(name: String = "CoreMIDIStub", destinationName: String? = nil, enableVirtualEndpoints: Bool = false, disableInput: Bool = true) {}
    public func open() throws {
        #if DEBUG
        print("[CoreMIDITransport-Stub] open (loopback)")
        #endif
        loop.onReceiveUMP = { [weak self] in self?.onReceiveUMP?($0) }
    }
    public func close() throws {}
    public func send(umpWords: [UInt32]) throws { try loop.send(umpWords: umpWords) }

    // Legacy introspection helpers used by demo and ML tools.
    // In the CoreMIDI‑free stub we expose a minimal, loopback‑only view.
    public static func destinationNames() -> [String] {
        ["loopback"]
    }

    public static func sourceNames() -> [String] {
        ["loopback"]
    }
}
