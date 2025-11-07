import SwiftUI
import AppKit
import FountainStoreClient
import MetalViewKit
import CoreMIDI
import FountainAudioEngine

@main
struct QuietFrameSonifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("QuietFrame Sonify") {
            QuietFrameView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            if let inst = QuietFrameInstrument.shared.instrument {
                inst.sendCC(controller: 123, value7: 0) // All Notes Off, best-effort
            }
        }
    }
}

struct QuietFrameView: View {
    @State private var saliency: Double = 0
    private let frameSize = CGSize(width: 1024, height: 1536)
    @State private var muted: Bool = false
    @State private var bpm: Double = 96
    @State private var section: Int = 1
    @State private var midiEvents: [String] = []
    @StateObject private var recorder = QuietFrameRecorder()
    @StateObject private var sidecar = SidecarInbound()
    @State private var act: Int = 1
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Main content
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                    VStack {
                        Spacer()
                    ZStack {
                        QuietFrameShape()
                            .fill(Color.white)
                            .overlay(
                                QuietFrameShape()
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                            .frame(width: frameSize.width, height: frameSize.height)
                        if act == 1 {
                            MouseTracker(onMove: { p in updateSaliency(point: p) })
                                .frame(width: frameSize.width, height: frameSize.height)
                                .allowsHitTesting(true)
                        } else {
                            CellsView(frameSize: frameSize)
                                .frame(width: frameSize.width, height: frameSize.height)
                                .allowsHitTesting(false)
                        }
                    }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .trailing) {
                        HStack(spacing: 10) {
                            Text(String(format: "saliency: %.3f", saliency)).monospaced().font(.caption)
                            ProgressView(value: saliency).frame(width: 140)
                            Divider().frame(height: 14)
                            HStack(spacing: 6) {
                                Text("Sec").font(.caption2)
                                Stepper(value: $section, in: 1...9, step: 1) {
                                    Text("\(section)").font(.caption2).monospaced()
                                }
                                .onChange(of: section) { _, v in
                                    FountainAudioEngine.shared.setParam(name: "act.section", value: Double(v))
                                }
                                Divider().frame(height: 12)
                                Text("BPM").font(.caption2)
                                Slider(value: $bpm, in: 60...180, step: 1)
                                    .frame(width: 120)
                                    .onChange(of: bpm) { _, v in
                                        FountainAudioEngine.shared.setParam(name: "tempo.bpm", value: v)
                                    }
                                Text("\(Int(bpm))").font(.caption2).monospaced()
                            }
                        Divider().frame(height: 14)
                        HStack(spacing: 8) {
                            Text("Act").font(.caption2)
                            Picker("Act", selection: $act) {
                                Text("I").tag(1)
                                Text("II").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            .onChange(of: act) { _, v in
                                if v == 2 {
                                    printActIIPrompts()
                                    // Ensure we hear Act II immediately
                                    FountainAudioEngine.shared.setParam(name: "engine.masterGain", value: 0.20)
                                    CellAutomataSim.shared.setRunning(true)
                                }
                            }
                            if act == 2 {
                                Divider().frame(height: 12)
                                Button(action: { CellAutomataSim.shared.setRunning(true) }) { Text("Run").font(.caption) }
                                Button(action: { CellAutomataSim.shared.setRunning(false) }) { Text("Pause").font(.caption) }
                                Button(action: { CellAutomataSim.shared.stepOnce() }) { Text("Step").font(.caption) }
                                HStack(spacing: 6) {
                                    Text("Hz").font(.caption2)
                                    Slider(value: Binding(get: { CellAutomataSim.shared.stepHz }, set: { CellAutomataSim.shared.setStepHz($0) }), in: 1...30, step: 1).frame(width: 120)
                                    Text("\(Int(CellAutomataSim.shared.stepHz))").font(.caption2).monospaced()
                                }
                            }
                        }
                        Button {
                            muted.toggle()
                            if muted { forceSilence() }
                        } label: {
                            Label(muted ? "Muted" : "Mute", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                        }
                        Button {
                            panicAllNotes()
                        } label: {
                            Label("Panic", systemImage: "exclamationmark.triangle")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                        }
                        Button {
                            testPing()
                        } label: {
                            Label("Test", systemImage: "waveform")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                        }
                        }
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(10)
                        // Place the monitor HUD under the primary controls (top-right)
                        MidiMonitorHUD()
                            .frame(width: 320)
                            .padding(.horizontal, 10)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                // MIDI feedback overlay (bottom-left)
                VStack(alignment: .leading, spacing: 4) {
                    Label("MIDI", systemImage: "music.note").font(.caption)
                    ForEach(midiEvents.suffix(6), id: \.self) { line in
                        Text(line).font(.caption2).monospaced()
                    }
                    HStack {
                        Spacer()
                        Button("Clear") { midiEvents.removeAll() }.font(.caption2)
                    }
                }
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 280)
                .padding(10)
                .overlay(
                    VStack(alignment: .leading, spacing: 12) {
                        Spacer()
                        MidiMonitorHUD()
                            .frame(maxWidth: 320)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(minWidth: 960, minHeight: 720)
        .onAppear {
            sendCC(value7: 0)
            if lastNote != 0 { QuietFrameInstrument.shared.instrument?.sendNoteOff(note: lastNote, velocity7: 0); lastNote = 0; lastTriggered = false }
            try? FountainAudioEngine.shared.start()
            FountainAudioEngine.shared.setParam(name: "tempo.bpm", value: bpm)
            FountainAudioEngine.shared.setParam(name: "act.section", value: Double(section))
            AudioOnsetToNotes.shared.start()
            Task { await NotesSSEClient.shared.start() }
            NotificationCenter.default.addObserver(forName: Notification.Name("QuietFrameRecordCommand"), object: nil, queue: .main) { n in
                let op = (n.userInfo?["op"] as? String) ?? ""
                Task { @MainActor in
                    if op == "start", let win = NSApp.mainWindow {
                        recorder.startRecording(window: win, rect: win.frame)
                    } else if op == "stop" {
                        recorder.stopRecording()
                    }
                }
            }
        }
    }

    private func updateSaliency(point: CGPoint) {
        guard point.x >= 0, point.y >= 0, point.x <= frameSize.width, point.y <= frameSize.height else {
            sendCC(value7: 0)
            saliency = 0
            return
        }
        let nx = Double(point.x / frameSize.width)
        let ny = Double(point.y / frameSize.height)
        let cx = frameSize.width * 0.5, cy = frameSize.height * 0.5
        let dx = Double(abs(point.x - cx)) / Double(max(1, frameSize.width) * 0.5)
        let dy = Double(abs(point.y - cy)) / Double(max(1, frameSize.height) * 0.5)
        let d = min(1.0, sqrt(dx*dx + dy*dy))
        let s = max(0, 1.0 - d)
        saliency = s
        if muted { forceSilence(); FountainAudioEngine.shared.setAmplitude(0); return }
        let v7 = UInt8(max(0, min(127, Int((s * 127.0).rounded()))))
        sendCC(value7: v7)
        // SDLKit engine follows saliency for immediate audibility
        FountainAudioEngine.shared.setFrequency(220 + s*660)
        FountainAudioEngine.shared.setAmplitude(min(0.25, max(0.0, s*0.2)))
        // Map saliency and position to timbre/density
        // x → brighter; y → density / space
        let tilt = nx // 0..1
        let density = ny
        FountainAudioEngine.shared.setParam(name: "drone.lpfHz", value: 300 + s*2200 + tilt*800)
        FountainAudioEngine.shared.setParam(name: "breath.level", value: 0.05 + density*0.3)
        FountainAudioEngine.shared.setParam(name: "fx.delay.mix", value: 0.02 + density*0.12)
        FountainAudioEngine.shared.setParam(name: "overtones.mix", value: smoothstep(0.35, 0.85, s))
        maybeTriggerNote(s)
    }

    private func sendCC(value7: UInt8) {
        if let inst = QuietFrameInstrument.shared.instrument { inst.sendCC(controller: 1, value7: value7) }
        MIDI1Out.shared.sendCC(cc: 1, value: value7)
        midiEvents.append("CC1 = \(value7)")
        MidiMonitorStore.shared.add("CC1 = \(value7)")
        SidecarBridge.shared.sendNoteEvent(["event":"cc","cc":1,"value":Int(value7),"channel":0,"group":0])
    }

    private var threshold: Double { 0.65 }
    @State private var lastNote: UInt8 = 0
    @State private var lastTriggered: Bool = false
    private func maybeTriggerNote(_ s: Double) {
        let inst = QuietFrameInstrument.shared.instrument
        if muted {
            if lastNote != 0 { inst?.sendNoteOff(note: lastNote, velocity7: 0); MIDI1Out.shared.sendNoteOff(note: lastNote); lastNote = 0 }
            lastTriggered = false
            return
        }
        let was = lastTriggered
        let now = s >= threshold
        if now && !was {
            let scale: [UInt8] = [60, 62, 65, 67, 69, 72]
            let idx = min(scale.count - 1, max(0, Int((s * Double(scale.count)).rounded())))
            let note = scale[idx]
            let vel: UInt8 = max(20, UInt8((s * 127).rounded()))
            inst?.sendNoteOn(note: note, velocity7: vel)
            MIDI1Out.shared.sendNoteOn(note: note, velocity: vel)
            midiEvents.append("NoteOn \(note) vel=\(vel)")
            MidiMonitorStore.shared.add("NoteOn n=\(note) v=\(vel)")
            SidecarBridge.shared.sendNoteEvent(["event":"noteOn","note":Int(note),"velocity":Int(vel),"channel":0,"group":0,"source":"saliency"])        
            lastNote = note
        } else if !now && was {
            if lastNote != 0 {
                inst?.sendNoteOff(note: lastNote, velocity7: 0)
                MIDI1Out.shared.sendNoteOff(note: lastNote)
                midiEvents.append("NoteOff \(lastNote)")
                MidiMonitorStore.shared.add("NoteOff n=\(lastNote)")
                SidecarBridge.shared.sendNoteEvent(["event":"noteOff","note":Int(lastNote),"channel":0,"group":0,"source":"saliency"])        
            }
            lastNote = 0
        }
        lastTriggered = now
    }

    private func forceSilence() {
        sendCC(value7: 0)
        if lastNote != 0 { QuietFrameInstrument.shared.instrument?.sendNoteOff(note: lastNote, velocity7: 0); MIDI1Out.shared.sendNoteOff(note: lastNote) }
        lastNote = 0
        lastTriggered = false
        FountainAudioEngine.shared.setAmplitude(0)
    }

    private func panicAllNotes() {
        QuietFrameInstrument.shared.instrument?.sendCC(controller: 123, value7: 0) // All Notes Off (Channel Mode)
        MIDI1Out.shared.allNotesOff()
        midiEvents.append("AllNotesOff")
        forceSilence()
    }

    private func testPing() {
        // Send a short CC1 max + note ping so we can verify audio path
        sendCC(value7: 127)
        let note: UInt8 = 72
        QuietFrameInstrument.shared.instrument?.sendNoteOn(note: note, velocity7: 100)
        MIDI1Out.shared.sendNoteOn(note: note, velocity: 100)
        midiEvents.append("NoteOn 72 vel=100 (test)")
        MidiMonitorStore.shared.add("NoteOn n=72 v=100 (test)")
        SidecarBridge.shared.sendNoteEvent(["event":"noteOn","note":72,"velocity":100,"channel":0,"group":0,"source":"test"])        
        FountainAudioEngine.shared.setFrequency(660)
        FountainAudioEngine.shared.setAmplitude(0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.sendCC(value7: 0)
            QuietFrameInstrument.shared.instrument?.sendNoteOff(note: note, velocity7: 0)
            MIDI1Out.shared.sendNoteOff(note: note)
            midiEvents.append("NoteOff 72 (test)")
            MidiMonitorStore.shared.add("NoteOff n=72 (test)")
            SidecarBridge.shared.sendNoteEvent(["event":"noteOff","note":72,"channel":0,"group":0,"source":"test"])        
            FountainAudioEngine.shared.setAmplitude(0)
        }
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0.0, min(1.0, (x - edge0) / max(0.000001, edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

// SDLKit engine is the default; no AVFoundation fallback.

// MARK: - MIDI1 stub (no CoreMIDI in QuietFrame)
@MainActor final class MIDI1Out { static let shared = MIDI1Out(); private init() {} ; func sendCC(cc: UInt8, value: UInt8, channel: UInt8 = 0) {} ; func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {} ; func sendNoteOff(note: UInt8, channel: UInt8 = 0) {} ; func allNotesOff(channel: UInt8 = 0) {} }

struct QuietFrameShape: Shape {
    func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: 6) }
}

// Removed global-coordinate reporter; we compute saliency in local 1024×1536 space.

// MARK: - Mouse tracker (AppKit)
struct MouseTracker: NSViewRepresentable {
    var onMove: (CGPoint) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.onMove = onMove
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class TrackingView: NSView {
        var onMove: ((CGPoint) -> Void)?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            let opts: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
            let ta = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
            addTrackingArea(ta)
        }
        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let p = convert(event.locationInWindow, from: nil)
            onMove?(p)
        }
    }
}

// Expose a single MIDI 2.0 instrument for the app
@MainActor final class QuietFrameInstrument {
    static let shared = QuietFrameInstrument()
    let instrument: MetalInstrument?
    init() {
        let sink = SonifyPESink()
        let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "QuietFrame", instanceId: "qf-1", displayName: "QuietFrame#qf-1")
        // Transport selection: prefer Loopback when integrating with MVK runtime
        if ProcessInfo.processInfo.environment["QF_USE_RUNTIME"] == "1" {
            MetalInstrument.setTransportOverride(LoopbackMetalInstrumentTransport.shared)
        } else if ProcessInfo.processInfo.environment["QF_TRANSPORT"] == "rtp" {
            MetalInstrument.setTransportOverride(MIDI2SystemInstrumentTransport(backend: .rtpFixedPort(5868)))
        } else {
            // Default: CoreMIDI virtual endpoints so tools/bridges can tap our UMP
            MetalInstrument.setTransportOverride(MIDI2SystemInstrumentTransport(backend: .coreMIDI))
        }
        let inst = MetalInstrument(sink: sink, descriptor: desc)
        inst.stateProvider = {
            var s = FountainAudioEngine.shared.snapshot()
            s["rec.state"] = QuietFrameRuntime.getRecState()
            // Include Act II numeric state for PE replies
            let cells = CellAutomataSim.shared.snapshotNumeric()
            for (k,v) in cells { s[k] = v }
            return s
        }
        inst.peProvider = { CellAutomataSim.shared.snapshotPE() }
        inst.enable()
        print("[quietframe-sonify] MVK instrument ready: displayName=\(desc.displayName) instanceId=\(desc.instanceId)")
        self.instrument = inst
    }
}

// MIDI 2.0 instrument sink that maps PE properties and CC to engine params
final class SonifyPESink: MetalSceneRenderer, MetalSceneUniformControls {
    func vendorEvent(topic: String, data: Any?) {
        if topic == "pe.string", let obj = data as? [String: Any], let name = obj["name"] as? String, let value = obj["value"] as? String {
            Task { @MainActor in CellAutomataSim.shared.setString(name: name, value: value) }
        }
    }
    func setUniform(_ name: String, float: Float) {
        Task { @MainActor in
            switch name {
            case "analysis.onset.thresholdRMS":
                AudioOnsetToNotes.shared.setThresholdRMS(float)
            case "analysis.onset.cooldownMs":
                AudioOnsetToNotes.shared.setCooldownMs(Double(float))
            case "analysis.onset.noteHoldMs":
                AudioOnsetToNotes.shared.setNoteHoldMs(Double(float))
            case _ where name.hasPrefix("cells."):
                CellAutomataSim.shared.set(name, value: Double(float))
            default:
                FountainAudioEngine.shared.setParam(name: name, value: Double(float))
            }
        }
    }
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, group: UInt8) {
        Task { @MainActor in
            if velocity == 0 {
                MidiMonitorStore.shared.add(String(format: "NoteOff n=%d ch=%d g=%d", note, channel, group))
                SidecarBridge.shared.sendNoteEvent(["event":"noteOff","note":Int(note),"channel":Int(channel),"group":Int(group)])
                FountainAudioEngine.shared.noteOff(note: note)
            } else {
                MidiMonitorStore.shared.add(String(format: "NoteOn n=%d v=%d ch=%d g=%d", note, velocity, channel, group))
                SidecarBridge.shared.sendNoteEvent(["event":"noteOn","note":Int(note),"velocity":Int(velocity),"channel":Int(channel),"group":Int(group)])
                FountainAudioEngine.shared.noteOn(note: note, velocity: velocity)
            }
        }
    }
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8, group: UInt8) {
        let v = Double(value) / 127.0
        Task { @MainActor in
            MidiMonitorStore.shared.add(String(format: "CC %d = %d ch=%d g=%d", controller, value, channel, group))
            SidecarBridge.shared.sendNoteEvent(["event":"cc","cc":Int(controller),"value":Int(value),"channel":Int(channel),"group":Int(group)])
            switch controller {
            case 1: FountainAudioEngine.shared.setParam(name: "engine.masterGain", value: v)
            case 7: FountainAudioEngine.shared.setParam(name: "engine.masterGain", value: v)
            case 74: FountainAudioEngine.shared.setParam(name: "drone.lpfHz", value: 300 + v * 3000)
            default: break
            }
        }
    }
    func pitchBend(value14: UInt16, channel: UInt8, group: UInt8) {
        Task { @MainActor in
            MidiMonitorStore.shared.add(String(format: "PB v14=%d ch=%d g=%d", value14, channel, group))
            SidecarBridge.shared.sendNoteEvent(["event":"pb","value14":Int(value14),"channel":Int(channel),"group":Int(group)])
            FountainAudioEngine.shared.pitchBend(value14: value14)
        }
    }
}

// MARK: - Prompt printing (Act II)
fileprivate func makeStoreClient() -> FountainStoreClient {
    let env = ProcessInfo.processInfo.environment
    if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
        let url: URL = dir.hasPrefix("~") ? URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true) : URL(fileURLWithPath: dir, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
    return FountainStoreClient(client: EmbeddedFountainStoreClient())
}

fileprivate func printActIIPrompts(corpus: String = ProcessInfo.processInfo.environment["CORPUS_ID"] ?? "quietframe-sonify") {
    Task { @MainActor in
        let store = makeStoreClient()
        let ids = ["prompt:quietframe-act2:teatro", "prompt:quietframe-act2:mrts", "prompt:quietframe-act2:facts"]
        for id in ids {
            if let data = try? await store.getDoc(corpusId: corpus, collection: "segments", id: id), let text = String(data: data, encoding: .utf8) {
                print("\n===== \(id) =====\n\(text)\n===== end \(id) =====\n")
            }
        }
    }
}
