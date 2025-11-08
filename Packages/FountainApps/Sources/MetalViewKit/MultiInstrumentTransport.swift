import Foundation

#if canImport(MIDI2Transports)
import MIDI2Transports
#endif

public final class MultiMetalInstrumentTransport: MetalInstrumentTransport, @unchecked Sendable {
    private let transports: [any MetalInstrumentTransport]

    public init(transports: [any MetalInstrumentTransport]) {
        self.transports = transports
    }

    public func makeSession(
        descriptor: MetalInstrumentDescriptor,
        receiveUMP: @escaping @Sendable ([UInt32]) -> Void
    ) throws -> MetalInstrumentTransportSession {
        let sessions: [any MetalInstrumentTransportSession] = try transports.map { t in
            try t.makeSession(descriptor: descriptor, receiveUMP: receiveUMP)
        }
        return MultiSession(children: sessions)
    }

    private final class MultiSession: MetalInstrumentTransportSession, @unchecked Sendable {
        private let children: [any MetalInstrumentTransportSession]
        private let lock = NSLock()
        private var closed = false
        init(children: [any MetalInstrumentTransportSession]) { self.children = children }
        func send(words: [UInt32]) {
            for s in children { s.send(words: words) }
        }
        func close() {
            lock.lock()
            if closed { lock.unlock(); return }
            closed = true
            lock.unlock()
            for s in children { s.close() }
        }
    }
}

