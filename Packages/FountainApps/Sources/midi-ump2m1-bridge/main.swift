import Foundation
import CoreMIDI

@main
struct UMP2M1Bridge {
    static func main() throws {
        var srcMatch: String = "QuietFrame"
        var mirrorDest: String? = nil
        var listDests = false
        var autoDest = false
        for arg in CommandLine.arguments.dropFirst() {
            if arg.hasPrefix("--source=") { srcMatch = String(arg.split(separator: "=", maxSplits: 1).last ?? "QuietFrame") }
            else if arg.hasPrefix("--mirror-dest=") { mirrorDest = String(arg.split(separator: "=", maxSplits: 1).last ?? "") }
            else if arg == "--list-dests" { listDests = true }
            else if arg == "--auto-dest" { autoDest = true }
        }
        if listDests {
            for name in Bridge.listDestinations() { print(name) }
            return
        }
        if autoDest, mirrorDest == nil { mirrorDest = Bridge.pickAutoDestination() }
        try Bridge(sourceContains: srcMatch, mirrorDestination: mirrorDest).run()
        RunLoop.main.run()
    }
}

final class Bridge {
    private var client: MIDIClientRef = 0
    private var inPort: MIDIPortRef = 0
    private var virtSrc: MIDIEndpointRef = 0
    private var mirrorDest: MIDIEndpointRef = 0
    private var connected = false
    private var timer: DispatchSourceTimer?
    private let name = "UMP2M1Bridge"
    private let match: String
    private let mirrorDestName: String?

    init(sourceContains: String, mirrorDestination: String?) { self.match = sourceContains; self.mirrorDestName = mirrorDestination }

    func run() throws {
        try check(MIDIClientCreateWithBlock(name as CFString, &client) { _ in })
        if #available(macOS 13.0, *) {
            try check(MIDIInputPortCreateWithProtocol(client, (name+"_in") as CFString, ._2_0, &inPort, { [weak self] (list, _) in
                self?.onEventList(list)
            }))
        } else {
            fatalError("Requires macOS 13+")
        }
        try check(MIDISourceCreate(client, (name+" (1.0)") as CFString, &virtSrc))
        if let dn = mirrorDestName, !dn.isEmpty {
            mirrorDest = findDestination(named: dn) ?? 0
            if mirrorDest != 0 { print("bridge: mirroring to dest=\(displayName(mirrorDest) ?? dn)") }
            else { print("bridge: mirror destination not found: \(dn)") }
        }
        _ = connectMatchingSource()
        if !connected {
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + 1.0, repeating: 1.0)
            t.setEventHandler { [weak self] in
                guard let self else { return }
                if !self.connected { _ = self.connectMatchingSource() }
                else { self.timer?.cancel(); self.timer = nil }
            }
            t.resume(); timer = t
        }
        print("bridge: listening to MIDI 2.0 source containing \"\(match)\" → publishing MIDI 1.0 source \(displayName(virtSrc) ?? "(unnamed)")")
    }

    @discardableResult
    private func connectMatchingSource() -> Bool {
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let s = MIDIGetSource(i)
            if let n = displayName(s), n.localizedCaseInsensitiveContains(match) {
                MIDIPortConnectSource(inPort, s, nil)
                connected = true
                print("bridge: connected to \(n)")
                return true
            }
        }
        print("bridge: no MIDI 2.0 source matched \"\(match)\"; will still run (connect manually if desired)")
        return false
    }

    private func onEventList(_ listPtr: UnsafePointer<MIDIEventList>) {
        var packet = listPtr.pointee.packet
        for _ in 0..<listPtr.pointee.numPackets {
            let count = Int(packet.wordCount)
            if count > 0 {
                // Interpret first word as UMP header
                let w1 = withUnsafePointer(to: packet.words) { ptr in UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt32.self).pointee }
                let mt = UInt8((w1 >> 28) & 0xF)
                if mt == 0x4 { // MIDI 2.0 Channel Voice
                    let group = UInt8((w1 >> 24) & 0xF)
                    let statusHi = UInt8((w1 >> 20) & 0xF) << 4
                    let ch = UInt8((w1 >> 16) & 0xF)
                    let data = UnsafeRawPointer(withUnsafePointer(to: packet.words) { $0 }).advanced(by: 8).assumingMemoryBound(to: UInt32.self)
                    // Convert to MIDI 1.0 3-byte messages
                    var bytes: [UInt8] = []
                    if statusHi == 0x90 {
                        let note = UInt8((w1 >> 8) & 0xFF)
                        let v16 = UInt16((data.pointee >> 16) & 0xFFFF)
                        let vel7 = UInt8((UInt32(v16) * 127) / 65535)
                        bytes = [0x90 | ch, note, vel7]
                    } else if statusHi == 0x80 {
                        let note = UInt8((w1 >> 8) & 0xFF)
                        bytes = [0x80 | ch, note, 0]
                    } else if statusHi == 0xB0 { // CC
                        let cc = UInt8((w1 >> 8) & 0xFF)
                        let v32 = data.pointee
                        let v7 = UInt8((Double(v32) / 4294967295.0 * 127.0).rounded())
                        bytes = [0xB0 | ch, cc, v7]
                    } else if statusHi == 0xE0 { // PB
                        let v32 = data.pointee
                        let v14 = UInt16((Double(v32) / 4294967295.0 * 16383.0).rounded())
                        let lsb = UInt8(v14 & 0x7F)
                        let msb = UInt8((v14 >> 7) & 0x7F)
                        bytes = [0xE0 | ch, lsb, msb]
                    }
                    if !bytes.isEmpty { sendMIDI1(bytes: bytes) }
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func sendMIDI1(bytes: [UInt8]) {
        var pktList = MIDIPacketList()
        withUnsafeMutablePointer(to: &pktList) { ptr in
            let pkt = MIDIPacketListInit(ptr)
            _ = MIDIPacketListAdd(ptr, 1024, pkt, 0, bytes.count, bytes)
            MIDIReceived(virtSrc, ptr)
            if mirrorDest != 0 { MIDISend(outPort, mirrorDest, ptr) }
        }
    }

    private func displayName(_ obj: MIDIObjectRef) -> String? {
        var param: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &param) == noErr {
            return param?.takeRetainedValue() as String?
        }
        return nil
    }

    private func findDestination(named name: String) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let d = MIDIGetDestination(i)
            if let n = displayName(d), n.localizedCaseInsensitiveContains(name) { return d }
        }
        return nil
    }

    // Static helpers for scripting
    static func listDestinations() -> [String] {
        var out: [String] = []
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let d = MIDIGetDestination(i)
            if let name = Bridge(sourceContains: "", mirrorDestination: nil).displayName(d) { out.append(name) }
        }
        return out
    }

    static func pickAutoDestination() -> String? {
        let prefs = ["AUM", "Bluetooth", "BLE", "Session", "iPad", "Network"]
        let names = listDestinations()
        for p in prefs { if let n = names.first(where: { $0.localizedCaseInsensitiveContains(p) }) { return n } }
        return names.first
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: "bridge", code: Int(status)) }
    }
}
