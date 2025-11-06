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

#if canImport(CoreMIDI)
import CoreMIDI

public enum CoreMIDIMetalTransportError: Error {
    case osStatus(OSStatus, String)
}

final class CoreMIDIMetalInstrumentSession: MetalInstrumentTransportSession, @unchecked Sendable {
    private var client: MIDIClientRef = 0
    private var source: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    private let receive: ([UInt32]) -> Void

    init(descriptor: MetalInstrumentDescriptor,
         receiveUMP: @escaping ([UInt32]) -> Void) throws {
        self.receive = receiveUMP
        let clientName = "\(descriptor.product)#\(descriptor.instanceId)" as CFString
        var tmpClient: MIDIClientRef = 0
        var status = MIDIClientCreateWithBlock(clientName, &tmpClient) { _ in }
        guard status == noErr else {
            throw CoreMIDIMetalTransportError.osStatus(status, "MIDIClientCreateWithBlock")
        }
        client = tmpClient

        var tmpSource: MIDIEndpointRef = 0
        status = MIDISourceCreateWithProtocol(client, descriptor.displayName as CFString, ._2_0, &tmpSource)
        guard status == noErr else {
            MIDIClientDispose(client)
            throw CoreMIDIMetalTransportError.osStatus(status, "MIDISourceCreateWithProtocol")
        }
        source = tmpSource

        var tmpDest: MIDIEndpointRef = 0
        status = MIDIDestinationCreateWithProtocol(client, descriptor.displayName as CFString, ._2_0, &tmpDest) { pktlist, _ in
            guard let pktlist else { return }
            for i in 0..<pktlist.numPackets {
                let pkt = pktlist.packet[Int(i)]
                if pkt.wordCount > 0 {
                    var words: [UInt32] = []
                    let ptr = UnsafeBufferPointer(start: pkt.words, count: Int(pkt.wordCount))
                    words.append(contentsOf: ptr)
                    receiveUMP(words)
                }
            }
        }
        guard status == noErr else {
            MIDIEndpointDispose(source)
            MIDIClientDispose(client)
            throw CoreMIDIMetalTransportError.osStatus(status, "MIDIDestinationCreateWithProtocol")
        }
        destination = tmpDest
    }

    func send(words: [UInt32]) {
        // Send as a single packet list (UMP 128-bit aligned)
        var words = words
        words.withUnsafeMutableBufferPointer { buf in
            var list = MIDIUDMCPacketList()
            list.protocol = ._2_0
            list.timeStamp = 0
            list.wordCount = UInt32(buf.count)
            withUnsafeMutablePointer(to: &list) { listPtr in
                buf.withMemoryRebound(to: UInt32.self) { ptr in
                    listPtr.pointee.packet.pointee.wordCount = UInt32(ptr.count)
                    memcpy(listPtr.pointee.packet.pointee.words, ptr.baseAddress, ptr.count * MemoryLayout<UInt32>.size)
                }
            }
            MIDIReceivedEventList(destination, &list)
        }
    }

    func close() {
        MIDIEndpointDispose(source)
        MIDIEndpointDispose(destination)
        MIDIClientDispose(client)
    }
}
#endif
