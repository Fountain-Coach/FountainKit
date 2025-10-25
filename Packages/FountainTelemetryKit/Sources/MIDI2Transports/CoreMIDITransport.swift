import Foundation

#if canImport(CoreMIDI)
import CoreMIDI

@available(macOS 13.0, *)
public final class CoreMIDITransport: MIDITransport {
    public var onReceiveUMP: (([UInt32]) -> Void)?

    private var client: MIDIClientRef = 0
    private var inPort: MIDIPortRef = 0
    private var outPort: MIDIPortRef = 0
    private var dest: MIDIEndpointRef = 0
    private var src: MIDIEndpointRef = 0
    private var inputConnected = false

    private let name: String
    private let destinationName: String?
    private let enableVirtualEndpoints: Bool

    public init(name: String = "FountainMIDI", destinationName: String? = nil, enableVirtualEndpoints: Bool = true) {
        self.name = name
        self.destinationName = destinationName
        self.enableVirtualEndpoints = enableVirtualEndpoints
    }

    public func open() throws {
        try check(MIDIClientCreateWithBlock(name as CFString, &client) { _ in })
        try check(MIDIInputPortCreateWithProtocol(client, (name+"_in") as CFString, MIDIProtocolID._2_0, &inPort, { [weak self] (list, srcConnRefCon) in
            self?.handleEventList(list)
        }))
        try check(MIDIOutputPortCreate(client, (name+"_out") as CFString, &outPort))

        if enableVirtualEndpoints {
            // Create a virtual source (apps can subscribe to receive from us)
            try check(MIDISourceCreateWithProtocol(client, (name+"_source") as CFString, MIDIProtocolID._2_0, &src))
            // Create a virtual destination (apps can send to us)
            try check(MIDIDestinationCreateWithProtocol(client, (name+"_dest") as CFString, MIDIProtocolID._2_0, &dest, { [weak self] (list, _) in
                self?.handleEventList(list)
            }))
        }

        // Auto-connect to first available external destination if none specified
        if let destinationName, let d = Self.findDestination(named: destinationName) {
            dest = d
        } else if dest == 0 {
            dest = Self.firstExternalDestination() ?? 0
        }

        // Connect all external sources to our inPort so we receive events
        connectAllSources()
    }

    public func close() throws {
        if inputConnected { MIDIClientDispose(client) }
        inputConnected = false
        client = 0; inPort = 0; outPort = 0; dest = 0; src = 0
    }

    public func send(umpWords: [UInt32]) throws {
        guard outPort != 0 else { return }
        guard dest != 0 else { return }

        // Build a single UMP in a MIDIEventList using API helpers
        let wordsCount = max(1, umpWords.count)
        let byteCount = MemoryLayout<MIDIEventList>.size + MemoryLayout<UInt32>.size * (wordsCount - 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { raw.deallocate() }
        let listPtr = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var cur = MIDIEventListInit(listPtr, ._2_0)
        umpWords.withUnsafeBufferPointer { buf in
            cur = MIDIEventListAdd(listPtr, byteCount, cur, 0, Int(buf.count), buf.baseAddress!)
        }
        if dest != 0 { try check(MIDISendEventList(outPort, dest, listPtr)) }
        if src != 0 { try check(MIDIReceivedEventList(src, listPtr)) }
    }

    private func handleEventList(_ listPtr: UnsafePointer<MIDIEventList>) {
        let list = listPtr.pointee
        var packet = list.packet
        for _ in 0..<list.numPackets {
            let count = Int(packet.wordCount)
            if count > 0 {
                var words: [UInt32] = []
                let base = withUnsafePointer(to: packet.words) { ptr in UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt32.self) }
                let buf = UnsafeBufferPointer(start: base, count: count)
                words.append(contentsOf: buf)
                if let cb = onReceiveUMP { cb(words) }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        guard count > 0 else { return }
        for i in 0..<count {
            let source = MIDIGetSource(i)
            if source != 0 {
                MIDIPortConnectSource(inPort, source, nil)
            }
        }
        inputConnected = true
    }

    public static func destinationNames() -> [String] {
        var names: [String] = []
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let d = MIDIGetDestination(i)
            if let name = getDisplayName(d) { names.append(name) }
        }
        return names
    }

    public static func sourceNames() -> [String] {
        var names: [String] = []
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let s = MIDIGetSource(i)
            if let name = getDisplayName(s) { names.append(name) }
        }
        return names
    }

    public static func firstExternalDestination() -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let d = MIDIGetDestination(i)
            return d
        }
        return nil
    }

    public static func findDestination(named name: String) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let d = MIDIGetDestination(i)
            if let n = getDisplayName(d), n == name { return d }
        }
        return nil
    }

    private static func getDisplayName(_ obj: MIDIObjectRef) -> String? {
        var param: Unmanaged<CFString>?
        let err = MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &param)
        if err == noErr, let name = param?.takeRetainedValue() { return name as String }
        return nil
    }

    @inline(__always)
    private func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: "CoreMIDITransport", code: Int(status), userInfo: nil) }
    }
}
#endif
