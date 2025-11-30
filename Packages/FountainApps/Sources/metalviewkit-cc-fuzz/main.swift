import Foundation
import MetalViewKit

@main
struct Main {
    static func main() async {
        do {
            try await run()
            print("{\"ok\":true,\"tool\":\"metalviewkit-cc-fuzz\"}")
            exit(0)
        } catch {
            fputs("metalviewkit-cc-fuzz failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        // Use loopback transport so we observe outgoing UMP directly
        MetalInstrument.setTransportOverride(LoopbackMetalInstrumentTransport.shared)

        final class NullSink: MetalSceneRenderer {
            func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {}
            func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {}
            func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {}
            func vendorEvent(topic: String, data: Any?) {}
        }

        let sink = NullSink()
        let desc = MetalInstrumentDescriptor(
            manufacturer: "Fountain",
            product: "CCFuzz",
            instanceId: "ccfuzz-1",
            displayName: "CCFuzz#1",
            midiGroup: 0
        )
        let inst = MetalInstrument(sink: sink, descriptor: desc)
        inst.enable()

        guard let handle = LoopbackMetalInstrumentTransport.shared.waitForInstrument(displayNameContains: "CCFuzz", timeout: 2.0) else {
            throw NSError(domain: "cc-fuzz", code: 1, userInfo: [NSLocalizedDescriptionKey: "instrument not registered"])
        }

        final class Box: @unchecked Sendable { let lock = NSLock(); private var _w: [UInt32] = []; func set(_ w: [UInt32]) { lock.lock(); _w = w; lock.unlock() }; func get() -> [UInt32] { lock.lock(); let w = _w; lock.unlock(); return w } }
        let box = Box()
        handle.observeOutgoing { words in box.set(words) }

        // Fuzz CC across ranges; assert shape and monotonic value mapping
        let g = Int(desc.midiGroup)
        for ch in 0...15 { for ctrl in 0...127 {
            var prev: UInt32 = 0
            for v in 0...127 {
                inst.sendCC(controller: UInt8(ctrl), value7: UInt8(v), channel: UInt8(ch))
                // Observe result synchronously
                let words = box.get()
                guard words.count >= 2 else { throw err("no words emitted") }
                let w0 = words[0], w1 = words[1]
                // Validate nibble layout
                let mt = (w0 >> 28) & 0xF
                let gg = (w0 >> 24) & 0xF
                let stat = (w0 >> 20) & 0xF
                let cch = (w0 >> 16) & 0xF
                let cc = (w0 >> 8) & 0xFF
                if mt != 0x4 { throw err("mt!=4") }
                if gg != UInt32(g & 0xF) { throw err("group mismatch") }
                if stat != 0xB { throw err("status!=B") }
                if cch != UInt32(ch & 0xF) { throw err("chan mismatch") }
                if cc != UInt32(ctrl & 0x7F) { throw err("ctrl mismatch") }
                // Monotonic and bounds
                if v == 0 && w1 != 0 { throw err("v1 not zero at v=0") }
                if v == 127 && w1 != 0xFFFF_FFFF { /* allow approximation rounding to all-ones */ }
                if w1 < prev { throw err("non-monotonic") }
                prev = w1
            }
        }}

        // Fuzz Note On/Off velocity mapping and header layout
        for ch in 0...15 {
            for note in 0...127 {
                var prevOn: UInt32 = 0
                for v in 0...127 {
                    inst.sendNoteOn(note: UInt8(note), velocity7: UInt8(v), channel: UInt8(ch))
                    let words = box.get()
                    guard words.count >= 2 else { throw err("no words emitted for note on") }
                    let w0 = words[0], w1 = words[1]
                    let mt = (w0 >> 28) & 0xF
                    let gg = (w0 >> 24) & 0xF
                    let stat = (w0 >> 20) & 0xF
                    let cch = (w0 >> 16) & 0xF
                    let nn = (w0 >> 8) & 0xFF
                    if mt != 0x4 || gg != UInt32(g & 0xF) || stat != 0x9 || cch != UInt32(ch & 0xF) || nn != UInt32(note & 0x7F) {
                        throw err("note on header mismatch")
                    }
                    // w1 upper 16 bits carry v16; ensure non-decreasing
                    if w1 < prevOn { throw err("note on v16 non-monotonic") }
                    prevOn = w1
                }
                // Note off
                inst.sendNoteOff(note: UInt8(note), velocity7: 0, channel: UInt8(ch))
                let words = box.get()
                let w0 = words[0]
                let stat = (w0 >> 20) & 0xF
                if stat != 0x8 { throw err("note off status mismatch") }
            }
        }

        // Fuzz Pitch Bend mapping and header layout
        for ch in 0...15 {
            var prevPB: UInt32 = 0
            for v14 in stride(from: 0, through: 16383, by: 257) {
                inst.sendPitchBend(value14: UInt16(v14), channel: UInt8(ch))
                let words = box.get()
                guard words.count >= 2 else { throw err("no words emitted for pb") }
                let w0 = words[0], w1 = words[1]
                let mt = (w0 >> 28) & 0xF
                let gg = (w0 >> 24) & 0xF
                let stat = (w0 >> 20) & 0xF
                let cch = (w0 >> 16) & 0xF
                if mt != 0x4 || gg != UInt32(g & 0xF) || stat != 0xE || cch != UInt32(ch & 0xF) {
                    throw err("pb header mismatch")
                }
                if w1 < prevPB { throw err("pb non-monotonic") }
                prevPB = w1
            }
        }
    }

    static func err(_ s: String) -> Error { NSError(domain: "cc-fuzz", code: 2, userInfo: [NSLocalizedDescriptionKey: s]) }
}
