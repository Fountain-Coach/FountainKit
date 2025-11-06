import Foundation

#if canImport(MIDI2Transports)
import MIDI2Transports

public enum MIDI2SystemInstrumentTransportError: Error {
    case unavailable(String)
}

public final class MIDI2SystemInstrumentTransport: MetalInstrumentTransport, @unchecked Sendable {
    public enum Backend: Sendable {
        case automatic
        case loopback
        case coreMIDI
        case alsa
        case rtpFixedPort(UInt16)
    }

    private let backend: Backend

    public init(backend: Backend = .automatic) {
        self.backend = backend
    }

    public func makeSession(
        descriptor: MetalInstrumentDescriptor,
        receiveUMP: @escaping @Sendable ([UInt32]) -> Void
    ) throws -> MetalInstrumentTransportSession {
        let transport = try buildTransport(for: descriptor)
        return try MIDI2SystemInstrumentSession(
            transport: transport,
            descriptor: descriptor,
            receiveUMP: receiveUMP
        )
    }

    private func buildTransport(for descriptor: MetalInstrumentDescriptor) throws -> any MIDITransport {
        switch backend {
        case .loopback:
            return LoopbackTransport()
        case .rtpFixedPort(let port):
            #if canImport(Network)
            return RTPMidiSession(localName: descriptor.displayName, mtu: 1400, enableDiscovery: false, enableCINegotiation: true, listenPort: port)
            #else
            return LoopbackTransport()
            #endif
        case .coreMIDI:
            #if canImport(CoreMIDI)
            if #available(macOS 13.0, *) {
                return CoreMIDITransport(name: descriptor.displayName, destinationName: nil, enableVirtualEndpoints: true)
            }
            #endif
            return LoopbackTransport()
        case .alsa:
            #if os(Linux)
            return ALSATransport(useLoopback: true)
            #else
            return LoopbackTransport()
            #endif
        case .automatic:
            #if canImport(CoreMIDI)
            if #available(macOS 13.0, *) {
                return CoreMIDITransport(name: descriptor.displayName, destinationName: nil, enableVirtualEndpoints: true)
            }
            #endif
            #if os(Linux)
            return ALSATransport(useLoopback: true)
            #else
            return LoopbackTransport()
            #endif
        }
    }
}

private final class MIDI2SystemInstrumentSession: MetalInstrumentTransportSession, @unchecked Sendable {
    private var transport: any MIDITransport
    private let descriptor: MetalInstrumentDescriptor
    private let receive: @Sendable ([UInt32]) -> Void
    private let lock = NSLock()
    private var closed = false

    init(
        transport: any MIDITransport,
        descriptor: MetalInstrumentDescriptor,
        receiveUMP: @escaping @Sendable ([UInt32]) -> Void
    ) throws {
        self.transport = transport
        self.descriptor = descriptor
        self.receive = receiveUMP
        self.transport.onReceiveUMP = { words in
            receiveUMP(words)
        }
        do {
            try transport.open()
        } catch {
            throw MIDI2SystemInstrumentTransportError.unavailable("Failed to open transport for \(descriptor.displayName): \(error)")
        }
    }

    func send(words: [UInt32]) {
        do {
            try transport.send(umpWords: words)
        } catch {
            #if DEBUG
            print("MIDI2 transport send failed for \(descriptor.displayName):", error)
            #endif
        }
    }

    func close() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        lock.unlock()
        do {
            transport.onReceiveUMP = nil
            try transport.close()
        } catch {
            #if DEBUG
            print("MIDI2 transport close failed for \(descriptor.displayName):", error)
            #endif
        }
    }
}

#else

public final class MIDI2SystemInstrumentTransport: MetalInstrumentTransport, @unchecked Sendable {
    public enum Backend: Sendable { case automatic, loopback, coreMIDI, alsa }
    public init(backend: Backend = .automatic) {}
    public func makeSession(
        descriptor: MetalInstrumentDescriptor,
        receiveUMP: @escaping @Sendable ([UInt32]) -> Void
    ) throws -> MetalInstrumentTransportSession {
        throw MIDI2SystemInstrumentTransportError.unavailable("MIDI2Transports module unavailable")
    }
}

public enum MIDI2SystemInstrumentTransportError: Error {
    case unavailable(String)
}

#endif

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
