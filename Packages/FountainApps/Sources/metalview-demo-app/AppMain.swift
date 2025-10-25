import SwiftUI
import AppKit
import MetalViewKit
#if canImport(MIDI2)
import MIDI2
#endif
#if canImport(MIDI2Transports)
import MIDI2Transports
#endif

@main
struct MetalViewDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 480)
        }
    }

    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

struct ContentView: View {
    @State private var useTextured = true
    @State private var dualView = false
    @State private var linkViews = true
    @State private var rotationSpeed: Float = 0.35
    // Local audio synth controls
    @State private var audioEnabled = false
    @State private var audioVolume: Double = 0.2
    @State private var synth: SynthDevice? = nil
    #if canImport(MIDI2Transports)
    enum TransportMode: String, CaseIterable {
        case loopback = "Loopback"
        case rtp = "RTP"
        #if canImport(CoreMIDI)
        case coremidi = "CoreMIDI"
        #endif
    }
    @State private var midiEnabled = false
    @State private var mode: TransportMode = .loopback
    @State private var sessionName: String = "MetalViewDemo"
    @State private var host: String = "127.0.0.1"
    @State private var rtpPortText: String = "5004"
    @State private var rtpGroup: UInt8 = 0
    @State private var channel: UInt8 = 0
    @State private var sendOnDrag = false
    @State private var velocity: Int = 80
    @State private var lastSize: CGSize = .zero
    @State private var lb: LoopbackTransport? = nil
    @State private var rtp: RTPMidiSession? = nil
    @State private var sceneHandle: MetalSceneRenderer? = nil
    @State private var triHandle: MetalSceneRenderer? = nil
    @State private var quadHandle: MetalSceneRenderer? = nil
    // Instrument display names for per-view endpoints
    @State private var triInstName: String = "MetalTriangleView#Local"
    @State private var quadInstName: String = "MetalTexturedQuadView#Local"
    #if canImport(CoreMIDI)
    @State private var coreDestinations: [String] = []
    @State private var coreSources: [String] = []
    @State private var coreSelectedDest: String = ""
    @State private var coreUseVirtualEndpoints: Bool = true
    @State private var core: AnyObject? = nil // CoreMIDITransport instance (type hidden behind #if)
    // Inspector state
    @State private var inspectorListen: Bool = true
    @State private var triSnapshot: String = ""
    @State private var quadSnapshot: String = ""
    // Optional cross-links between view instruments
    @State private var triToQuadLink: AnyObject? = nil
    @State private var quadToTriLink: AnyObject? = nil
    #endif
    // Monitoring and logs
    @State private var monitorLocal = true
    @State private var logs: [String] = []
    private func log(_ s: String) { logs.append("\(Date()): \(s)"); if logs.count > 200 { logs.removeFirst(logs.count - 200) } }
    #endif
    // Three-pane horizontal layout (Mapping | Logs | Inspector)
    @ViewBuilder private var threePane: some View {
        HSplitView {
            // Pane 1: Instrument Map
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    InstrumentMapEditor(apply: applyInstrumentMap)
                }
                .padding(.horizontal, 4)
            }
            .frame(minWidth: 280)

            // Pane 2: MIDI Logs
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    GroupBox("MIDI Logs") {
                        VStack(alignment: .leading, spacing: 2) {
                            let recent = Array(logs.suffix(30))
                            ForEach(Array(recent.enumerated()), id: \.0) { _, line in
                                Text(line).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(minWidth: 260)

            // Pane 3: Inspector
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Button("CI Discover Views") { ciDiscoverViews() }
                        Text("Tri: \(triInstName)")
                        Text("Quad: \(quadInstName)").foregroundColor(.secondary)
                    }
                    #if canImport(MIDI2Transports) && canImport(CoreMIDI)
                    GroupBox("Inspector") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Listen to CoreMIDI sources", isOn: $inspectorListen)
                                .onChange(of: inspectorListen) { _, newVal in if newVal { startInspectorListening() } else { stopInspectorListening() } }
                            Text("Triangle Snapshot").font(.headline)
                            TextEditor(text: $triSnapshot)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 80, maxHeight: 120)
                            HStack { Button("Get") { inspectorGetSnapshot(for: triInstName) }; Button("Apply") { inspectorApplyJSON(for: triInstName, jsonText: triSnapshot) } }
                            Text("Quad Snapshot").font(.headline)
                            TextEditor(text: $quadSnapshot)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 80, maxHeight: 120)
                            HStack { Button("Get") { inspectorGetSnapshot(for: quadInstName) }; Button("Apply") { inspectorApplyJSON(for: quadInstName, jsonText: quadSnapshot) } }
                        }
                    }
                    #endif
                }
                .padding(.horizontal, 4)
            }
            .frame(minWidth: 320)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("MetalViewKit")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)

            ZStack {
                if dualView {
                    HStack(alignment: .center, spacing: 12) {
                        MetalTriangleView(
                            onReady: { triHandle = $0; sceneHandle = $0 },
                            instrument: .init(manufacturer: "Fountain", product: "MetalTriangle", displayName: triInstName)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.black)

                        MetalTexturedQuadView(
                            rotationSpeed: rotationSpeed,
                            onReady: { quadHandle = $0; sceneHandle = $0 },
                            instrument: .init(manufacturer: "Fountain", product: "MetalQuad", displayName: quadInstName)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.black)
                    }
                } else {
                    if useTextured {
                        MetalTexturedQuadView(
                            rotationSpeed: rotationSpeed,
                            onReady: { sceneHandle = $0; quadHandle = $0 },
                            instrument: .init(manufacturer: "Fountain", product: "MetalQuad", displayName: quadInstName)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.black)
                    } else {
                        MetalTriangleView(
                            onReady: { sceneHandle = $0; triHandle = $0 },
                            instrument: .init(manufacturer: "Fountain", product: "MetalTriangle", displayName: triInstName)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.black)
                    }
                }
            }
            .background(Color.black.opacity(0.9))
            .cornerRadius(8)
            #if canImport(MIDI2Transports)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { lastSize = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in lastSize = newSize }
            })
            #endif
            #if canImport(MIDI2Transports)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard sendOnDrag, midiEnabled else { return }
                    let w = max(1.0, Double(lastSize.width == 0 ? 640 : lastSize.width))
                    let x = max(0.0, min(1.0, Double(value.location.x) / w))
                    velocity = Int((x * 127.0).rounded())
                    sendVelocityUMP(velocity)
                }
            )
            #endif

            Text("MetalViewKit demo — triangle vs. textured quad (with depth + uniforms)")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            // Three-pane horizontal layout
            threePane

            if false { // legacy stacked layout (kept for reference)
            DisclosureGroup("Instrument Map") {
                InstrumentMapEditor(apply: applyInstrumentMap)
            }.padding(.horizontal, 4)

            DisclosureGroup("MIDI Logs") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        let recent = Array(logs.suffix(30))
                        ForEach(Array(recent.enumerated()), id: \.0) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .frame(minHeight: 90, maxHeight: 140)
            }
            HStack(spacing: 12) {
                Button("CI Discover Views") { ciDiscoverViews() }
                Text("Tri: \(triInstName)")
                Text("Quad: \(quadInstName)")
                    .foregroundColor(.secondary)
            }
            #if canImport(MIDI2Transports) && canImport(CoreMIDI)
            GroupBox("Inspector") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Listen to CoreMIDI sources", isOn: $inspectorListen)
                        .onChange(of: inspectorListen) { _, newVal in if newVal { startInspectorListening() } else { stopInspectorListening() } }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Triangle Snapshot").font(.headline)
                            TextEditor(text: $triSnapshot)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 80, maxHeight: 120)
                            HStack {
                                Button("Get") { inspectorGetSnapshot(for: triInstName) }
                                Button("Apply") { inspectorApplyJSON(for: triInstName, jsonText: triSnapshot) }
                            }
                        }
                        VStack(alignment: .leading) {
                            Text("Quad Snapshot").font(.headline)
                            TextEditor(text: $quadSnapshot)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 80, maxHeight: 120)
                            HStack {
                                Button("Get") { inspectorGetSnapshot(for: quadInstName) }
                                Button("Apply") { inspectorApplyJSON(for: quadInstName, jsonText: quadSnapshot) }
                            }
                        }
                    }
                }
            }
            #endif
            } // end legacy layout
        }
        .padding(12)
        #if canImport(MIDI2Transports)
        .onChange(of: midiEnabled) { _, newValue in
            if newValue { setupTransport() } else { teardownTransport() }
        }
        .onChange(of: mode) { _, _ in if midiEnabled { setupTransport() } }
        .onChange(of: dualView) { _, _ in setupLinksIfNeeded() }
        .onChange(of: linkViews) { _, _ in setupLinksIfNeeded() }
        .onChange(of: rotationSpeed) { _, newValue in sceneHandle?.setUniform("rotationSpeed", float: newValue) }
        .onChange(of: audioEnabled) { _, newValue in if newValue { setupAudio() } else { teardownAudio() } }
        .onChange(of: audioVolume) { _, newValue in synth?.setVolume(newValue) }
        #if canImport(CoreMIDI)
        .onAppear { refreshCoreMIDIDestinations(); startInspectorListening(); setupLinksIfNeeded() }
        #endif
        #endif
        }
}

#if canImport(MIDI2Transports)
extension ContentView {
    private func setupTransport() {
        teardownTransport()
        switch mode {
        case .loopback:
            let t = LoopbackTransport()
            t.onReceiveUMP = { words in handleIncomingUMP(words) }
            lb = t
            // Seed
            sendVelocityUMP(velocity)
        case .rtp:
            let t = RTPMidiSession(localName: sessionName)
            t.onReceiveUMP = { words in handleIncomingUMP(words) }
            rtp = t
            try? t.open(); log("RTP opened")
            let p = UInt16(rtpPortText) ?? 5004
            try? t.connect(host: host, port: p); log("RTP connecting to \(host):\(p)")
            sendVelocityUMP(velocity)
        #if canImport(CoreMIDI)
        case .coremidi:
            if #available(macOS 13.0, *) {
                let destName = coreSelectedDest.isEmpty ? nil : coreSelectedDest
                let t = CoreMIDITransport(name: sessionName, destinationName: destName, enableVirtualEndpoints: coreUseVirtualEndpoints)
                t.onReceiveUMP = { words in handleIncomingUMP(words) }
                try? t.open(); log("CoreMIDI opened, dest=\(destName ?? "auto")")
                core = t as AnyObject
                sendVelocityUMP(velocity)
            }
        #endif
        }
        if audioEnabled { setupAudio() }
    }

    private func teardownTransport() {
        try? rtp?.close(); rtp = nil
        lb = nil
        #if canImport(CoreMIDI)
        core = nil
        #endif
        teardownAudio()
    }

    private func setupAudio() {
        if synth == nil {
            #if canImport(TeatroAudio)
            if let dev = TeatroSynthDevice() { synth = dev; log("Audio device: TeatroSynthDevice") } else { synth = LocalAudioSynthDevice(); log("Audio device: LocalAudioSynthDevice (fallback)") }
            #else
            synth = LocalAudioSynthDevice(); log("Audio device: LocalAudioSynthDevice")
            #endif
        }
        synth?.setVolume(audioVolume)
        synth?.start()
    }

    private func teardownAudio() {
        synth?.stop(); synth = nil
    }

    private func simulateNoteOn() {
        // For demo purposes, generate a pseudo velocity
        let v = Int.random(in: 10...120)
        let norm = max(0.0, min(1.0, Double(v) / 127.0))
        rotationSpeed = 0.05 + Float(norm) * 1.15
        sendVelocityUMP(v)
    }

    private func sendVelocityUMP(_ v: Int) {
        guard midiEnabled else { return }
        // Send MIDI 2.0 Channel Voice Note On (64-bit; 2 words)
        let msg = packMIDI2NoteOn(group: rtpGroup, channel: channel, note: 60, velocity7: UInt8(max(0, min(127, v))))
        var transport: (any MIDITransport)? = nil
        if let t = lb { transport = t }
        else if let t = rtp { transport = t }
        #if canImport(CoreMIDI)
        if transport == nil, let t = core as? (any MIDITransport) { transport = t }
        #endif
        if let t = transport { try? t.send(umpWords: msg); log("OUT \(summaryUMP(msg))") }
        if monitorLocal { handleIncomingUMP(msg); log("MON \(summaryUMP(msg))") }
    }

    private func ciDiscoverViews() {
        #if canImport(CoreMIDI)
        // Probe CoreMIDI destinations and send CI Discovery Inquiry (0x7E .. 0x0D 0x70) to our view endpoints if present
        if #available(macOS 13.0, *) {
            let dests = CoreMIDITransport.destinationNames()
            let targets = [triInstName, quadInstName]
            for target in targets {
                guard dests.contains(target) else { continue }
                let t = CoreMIDITransport(name: "Inspector", destinationName: target, enableVirtualEndpoints: false)
                try? t.open()
                // Build minimal Universal Non-Real-Time SysEx7 payload: 0x7E (Non-RT), 0x7F (All Call), 0x0D (MIDI-CI), 0x70 (Discovery Inquiry)
                let payload: [UInt8] = [0x7E, 0x7F, 0x0D, 0x70]
                let ump = packSysEx7UMP(group: rtpGroup, bytes: payload)
                try? t.send(umpWords: ump)
                log("CI Inquiry sent to \(target)")
            }
        }
        #endif
    }

    private func handleIncomingUMP(_ words: [UInt32]) {
        guard let w1 = words.first else { return }
        let type = UInt8((w1 >> 28) & 0xF)
        if type == 0x4 { // MIDI 2.0 Channel Voice (64-bit)
            let statusHi = UInt8((w1 >> 20) & 0xF) << 4
            let ch = UInt8((w1 >> 16) & 0xF)
            if statusHi == 0x90, words.count >= 2 { // Note On
                let note = UInt8((w1 >> 8) & 0xFF)
                let v16 = UInt16((words[1] >> 16) & 0xFFFF)
                let vel7 = UInt8((UInt32(v16) * 127) / 65535)
                if linkViews { triHandle?.noteOn(note: note, velocity: vel7, channel: ch, group: 0); quadHandle?.noteOn(note: note, velocity: vel7, channel: ch, group: 0) }
                sceneHandle?.noteOn(note: note, velocity: vel7, channel: ch, group: 0)
                instrumentMap?.applyNoteOn(note: note, vel: vel7) { key, value, mapping in applyUniform(key: key, value: value, mapping: mapping) }
                if audioEnabled { synth?.noteOn(note: note, velocity: vel7) }
                log("IN  M2 NoteOn ch=\(ch+1) note=\(note) v=\(vel7)")
            } else if statusHi == 0x80, words.count >= 2 { // Note Off (MIDI 2.0)
                let note = UInt8((w1 >> 8) & 0xFF)
                if audioEnabled { synth?.noteOff(note: note) }
                log("IN  M2 NoteOff ch=\(ch+1) note=\(note)")
            } else if statusHi == 0xB0, words.count >= 2 { // CC (32-bit value)
                let ctrl = UInt8((w1 >> 8) & 0xFF)
                let value32 = words[1]
                let v7 = UInt8((Double(value32) / 4294967295.0 * 127.0).rounded())
                if linkViews { triHandle?.controlChange(controller: ctrl, value: v7, channel: ch, group: 0); quadHandle?.controlChange(controller: ctrl, value: v7, channel: ch, group: 0) }
                sceneHandle?.controlChange(controller: ctrl, value: v7, channel: ch, group: 0)
                instrumentMap?.applyCC(cc: ctrl, value: v7) { key, value, mapping in applyUniform(key: key, value: value, mapping: mapping) }
                log("IN  M2 CC ch=\(ch+1) cc=\(ctrl) v=\(v7)")
            } else if statusHi == 0xE0, words.count >= 2 { // Pitch bend (32-bit)
                let v32 = words[1]
                let value14 = UInt16((Double(v32) / 4294967295.0 * 16383.0).rounded())
                if linkViews { triHandle?.pitchBend(value14: value14, channel: ch, group: 0); quadHandle?.pitchBend(value14: value14, channel: ch, group: 0) }
                sceneHandle?.pitchBend(value14: value14, channel: ch, group: 0)
                instrumentMap?.applyPitchBend(lsb: UInt8(value14 & 0x7F), msb: UInt8((value14 >> 7) & 0x7F)) { key, value, mapping in applyUniform(key: key, value: value, mapping: mapping) }
                if audioEnabled { synth?.pitchBend14(value14) }
                log("IN  M2 PB ch=\(ch+1) v14=\(value14)")
            }
        } else if type == 0x2 { // Fallback: MIDI 1.0 UMP (32-bit)
            let status = UInt8((w1 >> 16) & 0xFF)
            let data1 = UInt8((w1 >> 8) & 0xFF)
            let data2 = UInt8(w1 & 0xFF)
            let stHigh = status & 0xF0
            if stHigh == 0x90, data2 > 0 { // Note On
                if linkViews { triHandle?.noteOn(note: data1, velocity: data2, channel: status & 0x0F, group: 0); quadHandle?.noteOn(note: data1, velocity: data2, channel: status & 0x0F, group: 0) }
                sceneHandle?.noteOn(note: data1, velocity: data2, channel: status & 0x0F, group: 0)
                instrumentMap?.applyNoteOn(note: data1, vel: data2) { key, value, mapping in applyUniform(key: key, value: value, mapping: mapping) }
                if audioEnabled { synth?.noteOn(note: data1, velocity: data2) }
                log("IN  M1 NoteOn ch=\((status & 0x0F)+1) note=\(data1) v=\(data2)")
            } else if stHigh == 0x80 || (stHigh == 0x90 && data2 == 0) { // Note Off
                if audioEnabled { synth?.noteOff(note: data1) }
                log("IN  M1 NoteOff ch=\((status & 0x0F)+1) note=\(data1)")
            } else if stHigh == 0xB0 { // CC
                if linkViews { triHandle?.controlChange(controller: data1, value: data2, channel: status & 0x0F, group: 0); quadHandle?.controlChange(controller: data1, value: data2, channel: status & 0x0F, group: 0) }
                sceneHandle?.controlChange(controller: data1, value: data2, channel: status & 0x0F, group: 0)
                instrumentMap?.applyCC(cc: data1, value: data2) { key, value, mapping in applyUniform(key: key, value: value, mapping: mapping) }
                log("IN  M1 CC ch=\((status & 0x0F)+1) cc=\(data1) v=\(data2)")
            } else if stHigh == 0xE0 { // Pitch bend (14-bit)
                let pb = UInt16(data1) | (UInt16(data2) << 7)
                if linkViews { triHandle?.pitchBend(value14: pb, channel: status & 0x0F, group: 0); quadHandle?.pitchBend(value14: pb, channel: status & 0x0F, group: 0) }
                sceneHandle?.pitchBend(value14: pb, channel: status & 0x0F, group: 0)
                instrumentMap?.applyPitchBend(lsb: data1, msb: data2) { key, value, mapping in applyUniform(key: key, value: value, mapping: mapping) }
                if audioEnabled { synth?.pitchBend14(pb) }
                log("IN  M1 PB ch=\((status & 0x0F)+1) v14=\(pb)")
            }
        } else if type == 0x3 { // SysEx7 — Inspector: decode vendor JSON snapshots
            if let json = decodeSysEx7JSON(words: words) {
                log("CI RX: \(summarySysEx7(words)))")
                applyInspectorSnapshot(json)
            } else {
                log("CI RX: \(summarySysEx7(words)))")
            }
        }
    }

    private func packMidi1_0(type: UInt8, group: UInt8, status: UInt8, data1: UInt8, data2: UInt8) -> UInt32 {
        let t: UInt32 = UInt32(type & 0xF) << 28
        let g: UInt32 = UInt32(group & 0xF) << 24
        let st: UInt32 = UInt32(status) << 16
        let d1: UInt32 = UInt32(data1) << 8
        let d2: UInt32 = UInt32(data2)
        return t | g | st | d1 | d2
    }

    private func packMIDI2NoteOn(group: UInt8, channel: UInt8, note: UInt8, velocity7: UInt8) -> [UInt32] {
        let type: UInt32 = 0x4
        let attrType: UInt32 = 0 // none
        let w1 = (type << 28)
            | (UInt32(group & 0xF) << 24)
            | (UInt32(0x9) << 20)
            | (UInt32(channel & 0xF) << 16)
            | (UInt32(note) << 8)
            | attrType
        let vel16 = UInt32(velocity7) * 0x0101 // scale 7-bit to 16-bit
        let w2 = (vel16 << 16) | 0 // attribute data
        return [w1, w2]
    }

    private func packSysEx7UMP(group: UInt8, bytes: [UInt8]) -> [UInt32] {
        // Spec-correct SysEx7 UMP: 6 data bytes per packet; header encodes status + count.
        var words: [UInt32] = []
        let total = bytes.count
        let chunks: [[UInt8]] = stride(from: 0, to: total, by: 6).map { Array(bytes[$0..<min($0+6, total)]) }
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
            let w1 = UInt32(bigEndian: (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3]))
            let w2 = UInt32(bigEndian: (UInt32(b[4]) << 24) | (UInt32(b[5]) << 16) | (UInt32(b[6]) << 8) | UInt32(b[7]))
            words.append(w1); words.append(w2)
        }
        return words
    }

    private func summaryUMP(_ words: [UInt32]) -> String {
        guard let w1 = words.first else { return "[]" }
        let type = (w1 >> 28) & 0xF
        if type == 0x4 && words.count >= 2 {
            let stHi = (w1 >> 20) & 0xF
            let ch = (w1 >> 16) & 0xF
            let note = (w1 >> 8) & 0xFF
            if stHi == 0x9 { let v16 = (words[1] >> 16) & 0xFFFF; return "M2 NoteOn ch=\(ch+1) note=\(note) v16=\(v16)" }
            if stHi == 0x8 { return "M2 NoteOff ch=\(ch+1) note=\(note)" }
        } else if type == 0x2 {
            let st = (w1 >> 16) & 0xFF; let d1 = (w1 >> 8) & 0xFF; let d2 = w1 & 0xFF
            return String(format: "M1 st=%02X d1=%d d2=%d", st, d1, d2)
        }
        return String(format: "UMP type=%X words=%d", type, words.count)
    }

    private func summarySysEx7(_ words: [UInt32]) -> String {
        guard words.count >= 2 else { return "SysEx7 (short)" }
        // Decode first packet bytes
        let w1 = words[0]; let w2 = words[1]
        let b0 = UInt8((w1 >> 8) & 0xFF), b1 = UInt8(w1 & 0xFF)
        let b2 = UInt8((w2 >> 24) & 0xFF), b3 = UInt8((w2 >> 16) & 0xFF)
        if b0 == 0x7E && b1 == 0x7F && b2 == 0x0D { // Universal NR, Device All, MIDI-CI
            switch b3 {
            case 0x70: return "CI Discovery Inquiry"
            case 0x71: return "CI Discovery Reply"
            case 0x7F: return "CI Vendor Snapshot"
            default: return String(format: "CI sub:%02X", b3)
            }
        }
        return String(format: "SysEx7 b0=%02X b1=%02X b2=%02X b3=%02X", b0, b1, b2, b3)
    }
}
#endif

#if canImport(MIDI2Transports) && canImport(CoreMIDI)
extension ContentView {
    private func setupLinksIfNeeded() {
        if #available(macOS 13.0, *) {
            guard linkViews && dualView else { triToQuadLink = nil; quadToTriLink = nil; return }
            if triToQuadLink == nil {
                let t = CoreMIDITransport(name: "Tri→Quad", destinationName: quadInstName, enableVirtualEndpoints: false)
                try? t.open(); triToQuadLink = t as AnyObject
            }
            if quadToTriLink == nil {
                let t = CoreMIDITransport(name: "Quad→Tri", destinationName: triInstName, enableVirtualEndpoints: false)
                try? t.open(); quadToTriLink = t as AnyObject
            }
        }
    }
    private func startInspectorListening() {
        if #available(macOS 13.0, *) {
            if mode != .coremidi {
                let t = CoreMIDITransport(name: "InspectorListen", destinationName: nil, enableVirtualEndpoints: false)
                t.onReceiveUMP = { words in
                    if let json = decodeSysEx7JSON(words: words) { applyInspectorSnapshot(json) }
                }
                try? t.open()
                core = t as AnyObject
            }
        }
    }

    private func stopInspectorListening() {
        if mode != .coremidi { core = nil }
    }

    private func inspectorGetSnapshot(for destinationName: String) {
        if #available(macOS 13.0, *) {
            let t = CoreMIDITransport(name: "InspectorGet", destinationName: destinationName, enableVirtualEndpoints: false)
            try? t.open()
            // Build CI PE GET with requestId
            let requestId = UInt32.random(in: 1...0x0FFFFFFF)
            let body = MidiCiPropertyExchangeBody(command: .get, requestId: requestId, encoding: .json, header: [:], data: [])
            let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(body))
            let ump = packSysEx7UMP(group: rtpGroup, bytes: env.sysEx7Payload())
            try? t.send(umpWords: ump)
            log("CI TX: PE GET sent to \(destinationName)")
        }
    }

    private func inspectorApplyJSON(for destinationName: String, jsonText: String) {
        if #available(macOS 13.0, *) {
            guard let data = jsonText.data(using: .utf8) else { return }
            let t = CoreMIDITransport(name: "InspectorSet", destinationName: destinationName, enableVirtualEndpoints: false)
            try? t.open()
            let requestId = UInt32.random(in: 1...0x0FFFFFFF)
            let body = MidiCiPropertyExchangeBody(command: .set, requestId: requestId, encoding: .json, header: [:], data: [UInt8](data))
            let env = MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, version: 1, body: .propertyExchange(body))
            let ump = packSysEx7UMP(group: rtpGroup, bytes: env.sysEx7Payload())
            try? t.send(umpWords: ump)
            log("CI TX: PE SET sent to \(destinationName)")
        }
    }

    private func decodeSysEx7JSON(words: [UInt32]) -> [String: Any]? {
        var payload: [UInt8] = []
        for w in words { let be = w.bigEndian; withUnsafeBytes(of: be) { payload.append(contentsOf: $0) } }
        guard let s = payload.firstIndex(of: UInt8(ascii: "{")), let e = payload.lastIndex(of: UInt8(ascii: "}")), e > s else { return nil }
        let data = Data(payload[s...e])
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func applyInspectorSnapshot(_ json: [String: Any]) {
        var text = ""
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = String(describing: json)
        }
        if let id = json["identity"] as? [String: Any], let product = id["product"] as? String {
            if product.lowercased().contains("triangle") { triSnapshot = text }
            else if product.lowercased().contains("quad") { quadSnapshot = text }
            else { triSnapshot = text }
        } else {
            triSnapshot = text
        }
        log("INSPECTOR snapshot: \(text.prefix(60))...")
    }

    private func refreshCoreMIDIDestinations() {
        if #available(macOS 13.0, *) {
            coreDestinations = CoreMIDITransport.destinationNames()
            coreSources = CoreMIDITransport.sourceNames()
            if coreSelectedDest.isEmpty { coreSelectedDest = coreDestinations.first ?? "" }
            log("CoreMIDI Sources: \(coreSources.joined(separator: ", "))")
            log("CoreMIDI Dests: \(coreDestinations.joined(separator: ", "))")
        }
    }
}
#endif

// MARK: - Instrument mapping (JSON → behavior)
struct InstrumentMap: Codable {
    struct Range: Codable { var min: Float; var max: Float }
    struct NoteOnMap: Codable { var note: UInt8?; var range: Range }
    struct CCMap: Codable { var controller: UInt8; var range: Range }
    struct PitchBendMap: Codable { var range: Range }

    struct Mapping: Codable {
        var target: String
        var noteOn: NoteOnMap?
        var cc: CCMap?
        var pitchBend: PitchBendMap?
        // Operators (optional)
        var curve: String? // linear|exp|log|s-curve
        var smoothingMs: Double?
        var quantize: Float? // step (0..1 of normalized)
        var deadband: Float? // threshold (0..1)
        var offset: Float?
        var scale: Float?
        var invert: Bool?
    }

    var maps: [Mapping]

    func applyNoteOn(note: UInt8, vel: UInt8, to set: (String, Float, Mapping) -> Void) {
        for m in maps {
            guard let nm = m.noteOn else { continue }
            if let n = nm.note, n != note { continue }
            var norm = max(0, min(1, Float(vel) / 127.0))
            norm = shape(norm, with: m)
            let value = nm.range.min + norm * (nm.range.max - nm.range.min)
            set(m.target, value, m)
        }
    }
    func applyCC(cc ccnum: UInt8, value: UInt8, to set: (String, Float, Mapping) -> Void) {
        for m in maps {
            guard let cm = m.cc, cm.controller == ccnum else { continue }
            var norm = max(0, min(1, Float(value) / 127.0))
            norm = shape(norm, with: m)
            let value = cm.range.min + norm * (cm.range.max - cm.range.min)
            set(m.target, value, m)
        }
    }
    func applyPitchBend(lsb: UInt8, msb: UInt8, to set: (String, Float, Mapping) -> Void) {
        for m in maps {
            guard let pm = m.pitchBend else { continue }
            let v14 = UInt16(lsb) | (UInt16(msb) << 7)
            var norm = max(0, min(1, Float(v14) / 16383.0))
            norm = shape(norm, with: m)
            let value = pm.range.min + norm * (pm.range.max - pm.range.min)
            set(m.target, value, m)
        }
    }

    private func shape(_ x: Float, with m: Mapping) -> Float {
        var v = x
        if m.invert == true { v = 1.0 - v }
        if let curve = m.curve?.lowercased() {
            switch curve {
            case "exp": v = pow(max(0, v), 2.0)
            case "log": v = sqrt(max(0, v))
            case "s-curve": v = v * v * (3.0 - 2.0 * v)
            default: break // linear
            }
        }
        if let q = m.quantize, q > 0 { v = (round(v / q) * q) }
        if let db = m.deadband, db > 0, abs(v - 0.5) < db { v = 0.5 }
        if let s = m.scale { v *= s }
        if let o = m.offset { v += o }
        return max(0, min(1, v))
    }
}

// MARK: - Instrument map editor view
struct InstrumentMapEditor: View {
    @State private var text: String = InstrumentMapEditor.defaultJSON
    @State private var error: String = ""
    var apply: (InstrumentMap?) -> Void

    var body: some View {
        GroupBox("Instrument Map") {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 120)
                HStack {
                    Button("Apply") {
                        do {
                            let map = try JSONDecoder().decode(InstrumentMap.self, from: Data(text.utf8))
                            error = ""; apply(map)
                        } catch { self.error = String(describing: error); apply(nil) }
                    }
                    Button("Reset") { text = InstrumentMapEditor.defaultJSON; error = ""; apply(defaultMap) }
                    if !error.isEmpty { Text(error).foregroundColor(.red).lineLimit(1) }
                }
            }
        }
    }

    private var defaultMap: InstrumentMap { try! JSONDecoder().decode(InstrumentMap.self, from: Data(InstrumentMapEditor.defaultJSON.utf8)) }

    static let defaultJSON: String = """
    {"maps":[
      {"target":"rotationSpeed","noteOn":{"note":60,"range":{"min":0.05,"max":1.2}},"curve":"s-curve"},
      {"target":"zoom","cc":{"controller":2,"range":{"min":0.6,"max":1.6}},"smoothingMs":80},
      {"target":"tint.r","cc":{"controller":20,"range":{"min":0.0,"max":1.0}},"quantize":0.1},
      {"target":"tint.g","cc":{"controller":21,"range":{"min":0.0,"max":1.0}}},
      {"target":"tint.b","cc":{"controller":22,"range":{"min":0.0,"max":1.0}}},
      {"target":"brightness","cc":{"controller":23,"range":{"min":-0.5,"max":0.5}}},
      {"target":"exposure","cc":{"controller":24,"range":{"min":-2.0,"max":2.0}}},
      {"target":"contrast","cc":{"controller":25,"range":{"min":0.5,"max":2.0}}},
      {"target":"hue","cc":{"controller":26,"range":{"min":-3.14159,"max":3.14159}}},
      {"target":"saturation","cc":{"controller":27,"range":{"min":0.0,"max":2.0}}},
      {"target":"blurStrength","cc":{"controller":28,"range":{"min":0.0,"max":1.0}},"smoothingMs":120}
    ]}
    """
}

// MARK: - ContentView helpers for map
extension ContentView {
    @State private static var instrumentMapState: InstrumentMap? = try? JSONDecoder().decode(InstrumentMap.self, from: Data(InstrumentMapEditor.defaultJSON.utf8))
    var instrumentMap: InstrumentMap? { Self.instrumentMapState }
    private func applyInstrumentMap(_ map: InstrumentMap?) { Self.instrumentMapState = map }
    private static var lastUniformValues: [String: Float] = [:]
    private func applyUniform(key: String, value: Float, mapping: InstrumentMap.Mapping? = nil) {
        var v = value
        // Read previous value on main to avoid races
        var prevForSmoothing: Float = v
        if let m = mapping, let ms = m.smoothingMs, ms > 1 {
            if Thread.isMainThread {
                prevForSmoothing = Self.lastUniformValues[key] ?? v
            } else {
                var temp: Float = v
                DispatchQueue.main.sync { temp = Self.lastUniformValues[key] ?? v }
                prevForSmoothing = temp
            }
            let dt = 0.016
            let alpha = Float(dt / ((ms/1000.0) + dt))
            v = prevForSmoothing + alpha * (v - prevForSmoothing)
        }
        if let m = mapping, let q = m.quantize, q > 0 { v = (round(v / q) * q) }

        let applyOnMain = {
            Self.lastUniformValues[key] = v
            switch key {
            case "rotationSpeed":
                self.rotationSpeed = v
                self.sceneHandle?.setUniform("rotationSpeed", float: v)
            default:
                self.sceneHandle?.setUniform(key, float: v)
            }
        }
        if Thread.isMainThread { applyOnMain() } else { DispatchQueue.main.async(execute: applyOnMain) }
    }
}
