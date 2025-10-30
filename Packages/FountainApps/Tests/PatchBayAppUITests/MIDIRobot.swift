import Foundation
import XCTest
import MIDI2
import MetalViewKit
#if canImport(CoreMIDI)
import CoreMIDI
#endif

final class MIDIRobot {
    private enum Mode {
        case loopback(instanceId: String)
        #if canImport(CoreMIDI)
        case coreMIDI(client: MIDIClientRef, port: MIDIPortRef, destination: MIDIEndpointRef)
        #endif
    }

    private let mode: Mode
    private let clientName: CFString = "MIDIRobot" as CFString

    init?(destName: String = "PatchBay Canvas") {
        if let handle = LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: destName, timeout: 2.0) {
            mode = .loopback(instanceId: handle.descriptor.instanceId)
            return
        }

        #if canImport(CoreMIDI)
        var client: MIDIClientRef = 0
        guard MIDIClientCreateWithBlock(clientName, &client, { _ in }) == noErr else { return nil }
        var outPort: MIDIPortRef = 0
        guard MIDIOutputPortCreate(client, clientName, &outPort) == noErr else {
            MIDIClientDispose(client)
            return nil
        }
        var destination: MIDIEndpointRef = 0
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let ep = MIDIGetDestination(i)
            var name: Unmanaged<CFString>? = nil
            MIDIObjectGetStringProperty(ep, kMIDIPropertyName, &name)
            if let s = name?.takeRetainedValue() as String?, s.contains(destName) {
                destination = ep
                break
            }
        }
        if destination == 0 {
            MIDIPortDispose(outPort)
            MIDIClientDispose(client)
            return nil
        }
        mode = .coreMIDI(client: client, port: outPort, destination: destination)
        #else
        return nil
        #endif
    }

    // Send vendor JSON command as SysEx7 UMP with developer ID 0x7D
    func sendVendorJSON(topic: String, data: [String: Any]) {
        var payload: [UInt8] = [0xF0, 0x7D, 0x4A, 0x53, 0x4F, 0x4E, 0x00] // F0 7D 'JSON' 00
        let obj: [String: Any] = ["topic": topic, "data": data]
        let bytes = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        payload.append(contentsOf: bytes)
        payload.append(0xF7)
        sendSysEx7(bytes: payload)
    }

    func marqueeBegin(docX: Double, docY: Double, selectionMode: Int = 0) {
        sendVendorJSON(topic: "marquee.begin", data: [
            "origin.doc.x": docX,
            "origin.doc.y": docY,
            "selectionMode": selectionMode
        ])
    }

    func marqueeUpdate(docX: Double, docY: Double) {
        sendVendorJSON(topic: "marquee.update", data: [
            "current.doc.x": docX,
            "current.doc.y": docY
        ])
    }

    func marqueeEnd(docX: Double, docY: Double) {
        sendVendorJSON(topic: "marquee.end", data: [
            "current.doc.x": docX,
            "current.doc.y": docY
        ])
    }

    func marqueeCancel() {
        sendVendorJSON(topic: "marquee.cancel", data: [:])
    }

    deinit {
        #if canImport(CoreMIDI)
        if case .coreMIDI(let client, let port, _) = mode {
            MIDIPortDispose(port)
            MIDIClientDispose(client)
        }
        #endif
    }

    // Send MIDI-CI PE SET { properties:[{name,value},...] } via SysEx7 UMP
    func setProperties(_ props: [String: Double]) {
        var arr: [[String: Any]] = []
        for (k, v) in props { arr.append(["name": k, "value": v]) }
        let json = try! JSONSerialization.data(withJSONObject: ["properties": arr])
        let pe = MidiCiPropertyExchangeBody(command: .set, requestId: 1, encoding: .json, header: [:], data: Array(json))
        let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(pe))
        let bytes = env.sysEx7Payload()
        sendSysEx7(bytes: bytes)
    }

    private func sendSysEx7(bytes: [UInt8], group: UInt8 = 0) {
        // Build SysEx7 UMP packets (6-byte payload per packet)
        let chunks: [[UInt8]] = stride(from: 0, to: bytes.count, by: 6).map { Array(bytes[$0..<min($0+6, bytes.count)]) }
        var words: [UInt32] = []
        for (idx, chunk) in chunks.enumerated() {
            let isSingle = chunks.count == 1
            let isFirst = idx == 0
            let isLast = idx == chunks.count - 1
            let status: UInt8 = isSingle ? 0x0 : (isFirst ? 0x1 : (isLast ? 0x3 : 0x2))
            let num = UInt8(chunk.count)
            var b: [UInt8] = Array(repeating: 0, count: 8)
            b[0] = (0x3 << 4) | (group & 0xF)
            b[1] = (status << 4) | (num & 0xF)
            for i in 0..<min(6, chunk.count) { b[2 + i] = chunk[i] }
            let w1 = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
            let w2 = (UInt32(b[4]) << 24) | (UInt32(b[5]) << 16) | (UInt32(b[6]) << 8) | UInt32(b[7])
            words.append(w1); words.append(w2)
        }

        switch mode {
        case .loopback(let instanceId):
            _ = LoopbackMetalInstrumentTransport.shared.send(words: words, toInstanceId: instanceId)
        #if canImport(CoreMIDI)
        case .coreMIDI(_, let port, let destination):
            let byteCount = MemoryLayout<MIDIEventList>.size + MemoryLayout<UInt32>.size * (max(1, words.count) - 1)
            let raw = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<MIDIEventList>.alignment)
            defer { raw.deallocate() }
            let listPtr = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
            var cur = MIDIEventListInit(listPtr, MIDIProtocolID._2_0)
            words.withUnsafeBufferPointer { buf in
                cur = MIDIEventListAdd(listPtr, byteCount, cur, 0, buf.count, buf.baseAddress!)
            }
            MIDISendEventList(port, destination, listPtr)
        #endif
        }
    }
}
