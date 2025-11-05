import Foundation
import CoreMIDI
import MIDI2
import MIDI2CI

@main
struct QuietFrameSmoke {
    static func main() throws {
        let nameMatch = ProcessInfo.processInfo.environment["QF_NAME_CONTAINS"] ?? "Quiet Frame"
        let timeout = TimeInterval((ProcessInfo.processInfo.environment["QF_TIMEOUT"] as NSString?)?.doubleValue ?? 15)
        guard let dest = waitForDestination(containing: nameMatch, timeout: timeout) else {
            print("[smoke] No MIDI 2.0 destination containing \(nameMatch) found within \(timeout)s")
            exit(2)
        }
        let clientName = "QFSmoke" as CFString
        var client: MIDIClientRef = 0
        if MIDIClientCreate(clientName, nil, nil, &client) != noErr { fatalError("MIDIClientCreate failed") }
        var out: MIDIPortRef = 0
        if MIDIOutputPortCreate(client, "out" as CFString, &out) != noErr { fatalError("MIDIOutputPortCreate failed") }

        // 1) PE GET
        let getPE = MidiCiPropertyExchangeBody(command: .get, requestId: 1, encoding: .json, header: [:], data: [])
        let getEnv = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(getPE))
        sendSysEx7UMP(getEnv.sysEx7Payload(), out: out, dest: dest)
        print("[smoke] Sent PE GET")

        // 2) Start/Stop recording via vendor JSON
        sendVendorJSON(["topic":"rec.start"], out: out, dest: dest)
        print("[smoke] Sent rec.start")
        Thread.sleep(forTimeInterval: 1.0)
        sendVendorJSON(["topic":"rec.stop"], out: out, dest: dest)
        print("[smoke] Sent rec.stop")

        print("[smoke] OK")
    }

    static func waitForDestination(containing name: String, timeout: TimeInterval) -> MIDIEndpointRef? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let count = MIDIGetNumberOfDestinations()
            for i in 0..<count {
                let d = MIDIGetDestination(i)
                var cf: Unmanaged<CFString>?
                if MIDIObjectGetStringProperty(d, kMIDIPropertyDisplayName, &cf) == noErr {
                    let n = cf?.takeRetainedValue() as String? ?? ""
                    if n.localizedCaseInsensitiveContains(name) { return d }
                }
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return nil
    }

    static func sendSysEx7UMP(_ bytes: [UInt8], out: MIDIPortRef, dest: MIDIEndpointRef) {
        var words: [UInt32] = []
        var idx = 0
        while idx < bytes.count {
            let remain = bytes.count - idx
            let n = min(6, remain)
            let status: UInt8
            if idx == 0 && n == remain { status = 0x0 }
            else if idx == 0 { status = 0x2 }
            else if n == remain { status = 0x3 }
            else { status = 0x1 }
            var b = Array(bytes[idx..<(idx+n)])
            while b.count < 6 { b.append(0) }
            let w1 = (UInt32(0x3) << 28) | (UInt32(0) << 24) | (UInt32(status) << 20) | (UInt32(n) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w2 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words.append(w1); words.append(w2)
            idx += n
        }
        sendUMP(words, out: out, dest: dest)
    }

    static func sendVendorJSON(_ obj: [String: Any], out: MIDIPortRef, dest: MIDIEndpointRef) {
        guard let json = try? JSONSerialization.data(withJSONObject: obj) else { return }
        var bytes: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4E, 0x00]
        bytes.append(contentsOf: Array(json))
        bytes.append(0xF7)
        sendSysEx7UMP(bytes, out: out, dest: dest)
    }

    static func sendUMP(_ words: [UInt32], out: MIDIPortRef, dest: MIDIEndpointRef) {
        let listLen = MemoryLayout<MIDIEventList>.size + MemoryLayout<UInt32>.size * max(0, words.count - 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: listLen, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { raw.deallocate() }
        let listPtr = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var cur = MIDIEventListInit(listPtr, ._2_0)
        words.withUnsafeBufferPointer { buf in
            cur = MIDIEventListAdd(listPtr, listLen, cur, 0, buf.count, buf.baseAddress!)
        }
        MIDISendEventList(out, dest, listPtr)
    }
}

