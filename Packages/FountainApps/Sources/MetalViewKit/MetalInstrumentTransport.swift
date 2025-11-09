import Foundation

public protocol MetalInstrumentTransportSession: Sendable {
    func send(words: [UInt32])
    func close()
}

public protocol MetalInstrumentTransport: Sendable {
    func makeSession(descriptor: MetalInstrumentDescriptor,
                     receiveUMP: @escaping @Sendable ([UInt32]) -> Void) throws -> MetalInstrumentTransportSession
}

struct NoopMetalInstrumentSession: MetalInstrumentTransportSession {
    func send(words: [UInt32]) {}
    func close() {}
}

public struct NoopMetalInstrumentTransport: MetalInstrumentTransport {
    public init() {}
    public func makeSession(descriptor: MetalInstrumentDescriptor,
                             receiveUMP: @escaping @Sendable ([UInt32]) -> Void) throws -> MetalInstrumentTransportSession {
        _ = descriptor
        _ = receiveUMP
        return NoopMetalInstrumentSession()
    }
}

public struct LoopbackInstrumentHandle {
    fileprivate let session: LoopbackSession

    public var descriptor: MetalInstrumentDescriptor { session.descriptor }

    @discardableResult
    public func send(words: [UInt32]) -> Bool {
        session.deliver(words: words)
    }

    public func observeOutgoing(_ handler: @escaping @Sendable ([UInt32]) -> Void) {
        session.setOutgoingObserver(handler)
    }
}

public final class LoopbackMetalInstrumentTransport: MetalInstrumentTransport, @unchecked Sendable {
    public static let shared = LoopbackMetalInstrumentTransport()
    private let hub = LoopbackHub()

    private init() {}

    public func makeSession(descriptor: MetalInstrumentDescriptor,
                             receiveUMP: @escaping @Sendable ([UInt32]) -> Void) throws -> MetalInstrumentTransportSession {
        hub.register(descriptor: descriptor, receive: receiveUMP)
    }

    @discardableResult
    public func send(words: [UInt32], toDisplayName name: String) -> Bool {
        hub.session(displayNameContains: name)?.deliver(words: words) ?? false
    }

    @discardableResult
    public func send(words: [UInt32], toInstanceId instanceId: String) -> Bool {
        hub.session(instanceId: instanceId)?.deliver(words: words) ?? false
    }

    public func observeOutgoing(instanceId: String, handler: @escaping @Sendable ([UInt32]) -> Void) {
        hub.session(instanceId: instanceId)?.setOutgoingObserver(handler)
    }

    public func resolveDisplayName(_ name: String) -> LoopbackInstrumentHandle? {
        hub.session(displayNameContains: name).map { LoopbackInstrumentHandle(session: $0) }
    }

    public func waitForInstrument(displayNameContains name: String,
                                  timeout: TimeInterval,
                                  pollInterval: TimeInterval = 0.01) -> LoopbackInstrumentHandle? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let session = hub.session(displayNameContains: name) {
                return LoopbackInstrumentHandle(session: session)
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(pollInterval))
        } while Date() < deadline
        return nil
    }

    public func listDescriptors() -> [MetalInstrumentDescriptor] {
        hub.sessionDescriptors()
    }

    public func reset() {
        hub.reset()
    }
}

typealias LoopbackReceive = @Sendable ([UInt32]) -> Void
typealias LoopbackObserver = @Sendable ([UInt32]) -> Void

final class LoopbackSession: MetalInstrumentTransportSession, @unchecked Sendable {
    let descriptor: MetalInstrumentDescriptor
    private let receive: LoopbackReceive
    private let lock = NSLock()
    private var outgoingObserver: LoopbackObserver?
    private var closed = false
    private weak var hub: LoopbackHub?

    init(descriptor: MetalInstrumentDescriptor,
         receive: @escaping LoopbackReceive,
         hub: LoopbackHub) {
        self.descriptor = descriptor
        self.receive = receive
        self.hub = hub
    }

    func send(words: [UInt32]) {
        lock.lock()
        let observer = outgoingObserver
        lock.unlock()
        observer?(words)
    }

    func deliver(words: [UInt32]) -> Bool {
        guard !closed else { return false }
        receive(words)
        return true
    }

    func setOutgoingObserver(_ handler: @escaping LoopbackObserver) {
        lock.lock()
        outgoingObserver = handler
        lock.unlock()
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        hub?.remove(session: self)
    }
}

final class LoopbackHub: @unchecked Sendable {
    private var sessionsByInstance: [String: LoopbackSession] = [:]
    private let lock = NSLock()

    func register(descriptor: MetalInstrumentDescriptor,
                  receive: @escaping LoopbackReceive) -> LoopbackSession {
        let session = LoopbackSession(descriptor: descriptor, receive: receive, hub: self)
        lock.lock()
        sessionsByInstance[descriptor.instanceId] = session
        lock.unlock()
        return session
    }

    func remove(session: LoopbackSession) {
        lock.lock()
        sessionsByInstance.removeValue(forKey: session.descriptor.instanceId)
        lock.unlock()
    }

    func session(displayNameContains name: String) -> LoopbackSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByInstance.values.first { $0.descriptor.displayName.contains(name) }
    }

    func session(instanceId: String) -> LoopbackSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByInstance[instanceId]
    }

    func reset() {
        lock.lock()
        let values = sessionsByInstance.values
        sessionsByInstance.removeAll()
        lock.unlock()
        for session in values {
            session.close()
        }
    }

    func sessionDescriptors() -> [MetalInstrumentDescriptor] {
        lock.lock()
        let list = sessionsByInstance.values.map { $0.descriptor }
        lock.unlock()
        return list
    }
}

// CoreMIDI path disabled: provide a stub transport that uses Loopback.
public final class CoreMIDIMetalInstrumentTransport: MetalInstrumentTransport, @unchecked Sendable {
    public static let shared = CoreMIDIMetalInstrumentTransport()
    public init() {}
    public func makeSession(descriptor: MetalInstrumentDescriptor,
                             receiveUMP: @escaping @Sendable ([UInt32]) -> Void) throws -> MetalInstrumentTransportSession {
        return try LoopbackMetalInstrumentTransport.shared.makeSession(descriptor: descriptor, receiveUMP: receiveUMP)
    }
}
