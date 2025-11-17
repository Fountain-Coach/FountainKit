import SwiftUI
import AVFoundation
import MIDI2Transports

final class MPEOutput: ObservableObject {
    private var rtp: RTPMidiSession?
    #if canImport(CoreBluetooth)
    private var ble: BLEMidiTransport?
    #endif
    @Published var isOpen = false
    @Published var port: UInt16 = 5869
    @Published var group: UInt8 = 0
    @Published var bendRange: UInt8 = 48 // semitones
    @Published var useBLE: Bool = true
    @Published var bleFilter: String = "AUM"

    func open() {
        if isOpen { return }
        if useBLE {
            #if canImport(CoreBluetooth)
            let b = BLEMidiTransport(targetNameContains: bleFilter.isEmpty ? nil : bleFilter)
            try? b.open()
            ble = b
            isOpen = true
            for ch in 2...16 { sendRPNPitchBendRange(channel: UInt8(ch), semitones: bendRange) }
            #else
            openRTP()
            #endif
        } else { openRTP() }
    }
    private func openRTP() {
        let s = RTPMidiSession(localName: "Fountain MPE", enableDiscovery: true, enableCINegotiation: true, listenPort: port)
        try? s.open(); rtp = s; isOpen = true
        for ch in 2...16 { sendRPNPitchBendRange(channel: UInt8(ch), semitones: bendRange) }
    }
    func close() {
        try? rtp?.close(); rtp = nil
        #if canImport(CoreBluetooth)
        try? ble?.close(); ble = nil
        #endif
        isOpen = false
    }

    private func w(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, group g: UInt8) -> UInt32 {
        let mt: UInt32 = 0x2 << 28
        let grp: UInt32 = UInt32(g & 0x0F) << 24
        let st: UInt32 = UInt32(status)
        let b1: UInt32 = UInt32(d1)
        let b2: UInt32 = UInt32(d2)
        return mt | grp | (st << 16) | (b1 << 8) | b2
    }

    private func send(_ words: [UInt32]) {
        #if canImport(CoreBluetooth)
        if useBLE, let b = ble {
            for w in words { try? b.send(umpWords: [w]) }
            return
        }
        #endif
        try? rtp?.send(umps: words.chunked(4))
    }

    // CC helper
    private func cc(_ controller: UInt8, _ value: UInt8, channel: UInt8, group: UInt8) -> UInt32 {
        w(0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F, group: group)
    }

    // RPN 0,0 = pitch bend sensitivity; Data Entry coarse = semitones
    func sendRPNPitchBendRange(channel: UInt8, semitones: UInt8) {
        let g = group
        let msg = [
            cc(101, 0, channel: channel, group: g), // RPN MSB
            cc(100, 0, channel: channel, group: g), // RPN LSB
            cc(6, semitones, channel: channel, group: g), // Data Entry MSB (coarse)
            cc(38, 0, channel: channel, group: g), // Data Entry LSB (fine)
            cc(101, 127, channel: channel, group: g), // RPN null
            cc(100, 127, channel: channel, group: g)
        ]
        send(msg)
    }

    func noteOn(channel: UInt8, note: UInt8, velocity: UInt8) {
        send([w(0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F, group: group)])
    }
    func noteOff(channel: UInt8, note: UInt8, velocity: UInt8) {
        send([w(0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F, group: group)])
    }
    func pitchBend(channel: UInt8, value14: UInt16) {
        let lsb = UInt8(value14 & 0x7F)
        let msb = UInt8((value14 >> 7) & 0x7F)
        send([w(0xE0 | (channel & 0x0F), lsb, msb, group: group)])
    }
    func polyAftertouch(channel: UInt8, note: UInt8, pressure: UInt8) {
        send([w(0xA0 | (channel & 0x0F), note & 0x7F, pressure & 0x7F, group: group)])
    }
}

final class SimpleSine: ObservableObject {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    @Published var isRunning = false
    private var phase: Float = 0
    private var freq: Float = 440
    private var amp: Float = 0
    init() {
        source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let sr: Float = 48000
            let delta = (2 * Float.pi * self.freq) / sr
            for frame in 0..<Int(frameCount) {
                let s = sin(self.phase) * self.amp
                self.phase += delta
                for buf in abl { let ptr = buf.mData!.assumingMemoryBound(to: Float.self); ptr[frame] = s }
            }
            return noErr
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }
    func start() { try? engine.start(); isRunning = true }
    func stop() { engine.stop(); isRunning = false }
    func set(freq: Float, amp: Float) { self.freq = freq; self.amp = amp }
}

struct MPEPadInstrument: View {
    @StateObject private var out = MPEOutput()
    @StateObject private var synth = SimpleSine()
    @State private var active: Bool = false
    @State private var channel: UInt8 = 2 // MPE lower zone first member channel
    @State private var note: UInt8 = 60
    @State private var bend: UInt16 = 8192

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("MPE Pad").font(.system(size: 12, weight: .semibold))
                Picker("Link", selection: $out.useBLE) {
                    Text("BLE").tag(true); Text("RTP").tag(false)
                }.pickerStyle(.segmented).frame(width: 120)
                Toggle(out.useBLE ? "Open BLE" : "Open RTP", isOn: Binding(get: { out.isOpen }, set: { v in if v { out.open() } else { out.close() } }))
                if out.useBLE {
                    TextField("BLE filter", text: $out.bleFilter).textFieldStyle(.roundedBorder).frame(width: 160)
                } else {
                Stepper("Port \(out.port)", value: $out.port, in: 1024...65535)
                    .onChange(of: out.port) { _ in if out.isOpen { out.close(); out.open() } }
                }
                Stepper("Bend ±\(out.bendRange)", value: $out.bendRange, in: 2...96)
                    .onChange(of: out.bendRange) { v in if out.isOpen { for ch in 2...16 { out.sendRPNPitchBendRange(channel: UInt8(ch), semitones: v) } } }
                Spacer()
                Toggle("Local Audio", isOn: $active)
                    .onChange(of: active) { v in v ? synth.start() : synth.stop() }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.18), .purple.opacity(0.18)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .cornerRadius(8)
                    Text("Drag to play — X=pitch, Y=velocity; pressure=polyAT (hold Option and scroll to emulate)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    handleDrag(value: value, width: w, height: h)
                }.onEnded { _ in
                    out.pitchBend(channel: channel, value14: 8192)
                    out.noteOff(channel: channel, note: note, velocity: 0)
                    if active { synth.set(freq: 0, amp: 0) }
                })
            }
            .frame(height: 180)
        }
        .onAppear { if active { synth.start() } }
        .onDisappear { synth.stop(); out.close() }
    }

    private func handleDrag(value: DragGesture.Value, width w: CGFloat, height h: CGFloat) {
        if !out.isOpen { out.open() }
        let x = max(0, min(Double(value.location.x / w), 1))
        let y = max(0, min(1 - Double(value.location.y / h), 1))
        let base: UInt8 = 60
        let span: UInt8 = 24
        let noteNow = base &+ UInt8(Double(span) * y)
        let vel = UInt8(20 + (y * 100))
        if noteNow != note {
            out.noteOff(channel: channel, note: note, velocity: 0)
            note = noteNow
            out.noteOn(channel: channel, note: note, velocity: vel)
        }
        let deltaSemis = (x - 0.5) * Double(out.bendRange) * 2
        let value14 = UInt16(max(0, min(16383, Int(8192 + (deltaSemis / Double(out.bendRange) / 2) * 16383.0 * 2))))
        bend = value14
        out.pitchBend(channel: channel, value14: value14)
        out.polyAftertouch(channel: channel, note: note, pressure: vel)
        if active {
            let freq = 440.0 * pow(2.0, (Double(note) - 69.0 + deltaSemis) / 12.0)
            synth.set(freq: Float(freq), amp: Float(min(0.25, max(0.0, y * 0.25))))
        }
    }
}

private extension Array {
    func chunked(_ n: Int) -> [[Element]] {
        stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0+n, count)]) }
    }
}
