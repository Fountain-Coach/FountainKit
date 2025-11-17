import SwiftUI
import AVFoundation
import MIDI2Transports
import LauncherSignature
#if canImport(AppKit)
import AppKit
#endif

@main
struct MPEPadApp: App {
    init() {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if os(macOS)
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    #endif
                }
        }
    }
}

enum TransportMode: String, CaseIterable, Identifiable { case blePeripheral, bleCentral, rtp, sidecar; var id: String { rawValue } }

final class SinePreview: ObservableObject {
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

@MainActor
final class MPEPadOutput: ObservableObject {
    @Published var mode: TransportMode = .blePeripheral
    @Published var bleFilter: String = "AUM"
    @Published var rtpPort: UInt16 = 5869
    @Published var sidecarPort: UInt16 = 18090
    @Published var sidecarOnline: Bool = false
    @Published var sidecarDestinations: [String] = []
    @Published var selectedDestination: String = ""
    @Published var rtpEnabled: Bool = false
    @Published var rtpHost: String = "127.0.0.1"
    @Published var rtpConnPort: UInt16 = 5004
    @Published var bleName: String = "MPE Pad"
    @Published var bleAdvertising: Bool = false
    @Published var bendRange: UInt8 = 48
    @Published var isOpen = false
    @Published var baseChannel: UInt8 = 2
    #if canImport(CoreBluetooth)
    private var bleP: BLEMidiPeripheralTransport?
    private var bleC: BLEMidiTransport?
    #endif
    private var rtp: RTPMidiSession?
    private var reAdvTimer: DispatchSourceTimer?
    @Published var autoReAdvertise: Bool = true
    private var peripheralName: String = "MPE Pad"

    func open() {
        if isOpen { return }
        switch mode {
        case .blePeripheral:
            #if canImport(CoreBluetooth)
            let p = BLEMidiPeripheralTransport(advertisedName: peripheralName)
            try? p.open(); bleP = p
            isOpen = true
            applyBendRange()
            startReAdvTimer()
            #endif
        case .bleCentral:
            #if canImport(CoreBluetooth)
            let c = BLEMidiTransport(targetNameContains: bleFilter.isEmpty ? nil : bleFilter)
            try? c.open(); bleC = c
            isOpen = true
            applyBendRange()
            stopReAdvTimer()
            #endif
        case .rtp:
            let s = RTPMidiSession(localName: peripheralName, enableDiscovery: true, enableCINegotiation: true, listenPort: rtpPort)
            try? s.open(); rtp = s
            isOpen = true
            applyBendRange()
            stopReAdvTimer()
        case .sidecar:
            // No device open; we will POST MIDI 1.0 messages to the sidecar
            isOpen = true
            applyBendRange()
        }
    }
    func close() {
        #if canImport(CoreBluetooth)
        try? bleP?.close(); bleP = nil
        try? bleC?.close(); bleC = nil
        #endif
        try? rtp?.close(); rtp = nil
        isOpen = false
        stopReAdvTimer()
    }
    private func sendUMP(words: [UInt32]) {
        #if canImport(CoreBluetooth)
        if let p = bleP { try? p.send(umpWords: words) }
        if let c = bleC { try? c.send(umpWords: words) }
        #endif
        if let r = rtp { try? r.send(umps: [words]) }
        if mode == .sidecar {
            // Convert UMP to MIDI 1.0 and send to sidecar
            let msgs = convertUMPToMIDI1(ump: words)
            postToSidecar(messages: msgs)
        }
    }
    private func w(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, group g: UInt8 = 0) -> UInt32 {
        let mt: UInt32 = 0x2 << 28
        let grp: UInt32 = UInt32(g & 0x0F) << 24
        let st: UInt32 = UInt32(status)
        let b1: UInt32 = UInt32(d1)
        let b2: UInt32 = UInt32(d2)
        return mt | grp | (st << 16) | (b1 << 8) | b2
    }
    private func cc(_ controller: UInt8, _ value: UInt8, channel: UInt8) -> UInt32 { w(0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F) }
    private func applyBendRange() {
        for ch in baseChannel...16 {
            for (ctl,val) in MPEPadMapping.rpnPitchBendSensitivity(semitones: bendRange) {
                sendUMP(words: [cc(ctl, val, channel: UInt8(ch))])
            }
        }
    }
    func noteOn(note: UInt8, velocity: UInt8) { sendUMP(words: [w(0x90 | (baseChannel & 0x0F), note & 0x7F, velocity & 0x7F)]) }
    func noteOff(note: UInt8, velocity: UInt8) { sendUMP(words: [w(0x80 | (baseChannel & 0x0F), note & 0x7F, velocity & 0x7F)]) }
    func pitchBend(value14: UInt16) {
        let lsb = UInt8(value14 & 0x7F); let msb = UInt8((value14 >> 7) & 0x7F)
        sendUMP(words: [w(0xE0 | (baseChannel & 0x0F), lsb, msb)])
    }
    func polyAftertouch(note: UInt8, pressure: UInt8) { sendUMP(words: [w(0xA0 | (baseChannel & 0x0F), note & 0x7F, pressure & 0x7F)]) }

    func reAdvertiseNow() {
        #if canImport(CoreBluetooth)
        bleP?.restartAdvertising()
        #endif
    }

    func setAdvertisedName(_ s: String) { peripheralName = s }

    private func startReAdvTimer(interval: TimeInterval = 12.0) {
        stopReAdvTimer()
        #if canImport(CoreBluetooth)
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.autoReAdvertise, self.isOpen, self.mode == .blePeripheral else { return }
            if (self.bleP?.connectedCentralsCount ?? 0) == 0 { self.bleP?.restartAdvertising() }
        }
        t.resume()
        reAdvTimer = t
        #endif
    }
    private func stopReAdvTimer() { reAdvTimer?.cancel(); reAdvTimer = nil }

    // Expose lightweight status for UI
    var connectedCount: Int {
        #if canImport(CoreBluetooth)
        return bleP?.connectedCentralsCount ?? 0
        #else
        return 0
        #endif
    }
    var advertising: Bool {
        #if canImport(CoreBluetooth)
        return bleP?.isAdvertising ?? false
        #else
        return false
        #endif
    }

    // MARK: - Sidecar helpers (HTTP JSON)
    private func convertUMPToMIDI1(ump: [UInt32]) -> [[UInt8]] {
        guard !ump.isEmpty else { return [] }
        let mt = UInt8((ump[0] >> 28) & 0xF)
        switch mt {
        case 0x2: // MIDI 2.0 Channel Voice → reduce to MIDI 1.0 approx
            let status = UInt8((ump[0] >> 16) & 0xFF)
            let d1 = UInt8((ump[0] >> 8) & 0xFF)
            let d2 = UInt8(ump[0] & 0xFF)
            let hi = status & 0xF0
            return [(hi == 0xC0 || hi == 0xD0) ? [status, d1] : [status, d1, d2]]
        case 0x1: // System/Utility
            let status = UInt8((ump[0] >> 16) & 0xFF)
            let d1 = UInt8((ump[0] >> 8) & 0xFF)
            let d2 = UInt8(ump[0] & 0xFF)
            switch status {
            case 0xF8, 0xFA, 0xFB, 0xFC, 0xFE, 0xFF, 0xF6: return [[status]]
            case 0xF1, 0xF3: return [[status, d1]]
            case 0xF2: return [[status, d1, d2]]
            default: return [[status]]
            }
        case 0x3: // SysEx7
            var bytes: [UInt8] = [0xF0]
            // naive packing: we expect the payload to be extracted elsewhere; fall back empty
            bytes.append(0xF7)
            return [bytes]
        case 0x4: // MIDI 2.0 CV, treat via simple map (not used here)
            return []
        default:
            return []
        }
    }
    private func postToSidecar(messages: [[UInt8]]) {
        guard !messages.isEmpty else { return }
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/midi1/send") else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["messages": messages.map { $0.map { Int($0) } }]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }
    // Sidecar utilities
    func pingSidecar() {
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            Task { @MainActor in self.sidecarOnline = (data != nil) }
        }.resume()
    }
    func refreshDestinations() {
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/destinations") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var names: [String] = []
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = obj["items"] as? [[String: Any]] {
                names = items.compactMap { $0["name"] as? String }
            }
            Task { @MainActor in
                self.sidecarDestinations = names
                if !names.isEmpty && self.selectedDestination.isEmpty { self.selectedDestination = names[0] }
            }
        }.resume()
    }
    func selectDestination() {
        guard !selectedDestination.isEmpty else { return }
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/select-destination") else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": selectedDestination]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }
    func fetchRTPStatus() {
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/rtp/status") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Task { @MainActor in self.rtpEnabled = (obj["enabled"] as? Bool) ?? false }
            }
        }.resume()
    }
    func setRTPEnabled(_ enable: Bool) {
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/rtp/session") else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["enable": enable])
        URLSession.shared.dataTask(with: req) { _, _, _ in
            Task { @MainActor in self.rtpEnabled = enable }
        }.resume()
    }
    func connectRTP() {
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/rtp/connect") else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["host": rtpHost, "port": Int(rtpConnPort)])
        URLSession.shared.dataTask(with: req).resume()
    }
    func fetchBLEStatus() {
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/ble/status") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Task { @MainActor in self.bleAdvertising = (obj["advertising"] as? Bool) ?? false }
            }
        }.resume()
    }
    func setBLEAdvertising(_ enable: Bool) {
        let port = Int(sidecarPort)
        guard let url = URL(string: "http://127.0.0.1:\(port)/ble/advertise") else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["enable": enable, "name": bleName])
        URLSession.shared.dataTask(with: req) { _, _, _ in
            Task { @MainActor in self.bleAdvertising = enable }
        }.resume()
    }
}

struct ContentView: View {
    @StateObject private var out = MPEPadOutput()
    @StateObject private var sine = SinePreview()
    @State private var currentNote: UInt8 = 60
    @State private var dragging = false
    @State private var tick = 0
    @State private var periphName: String = "MPE Pad"
    private var statusLine: String {
        guard out.mode == .blePeripheral else { return "" }
        if !out.isOpen { return "Status: Closed" }
        let adv = out.advertising ? "Advertising" : "Idle"
        let cnt = out.connectedCount
        return "Status: \(adv) / Connected (\(cnt))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Transport", selection: $out.mode) {
                    Text("BLE Periph").tag(TransportMode.blePeripheral)
                    Text("BLE Central").tag(TransportMode.bleCentral)
                    Text("RTP").tag(TransportMode.rtp)
                    Text("Sidecar").tag(TransportMode.sidecar)
                }.pickerStyle(.segmented).frame(width: 300)
                if out.mode == .bleCentral {
                    TextField("BLE filter", text: $out.bleFilter).textFieldStyle(.roundedBorder).frame(width: 160)
                }
                if out.mode == .blePeripheral {
                    TextField("Name", text: $periphName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit { out.setAdvertisedName(periphName); if out.isOpen { out.close(); out.open() } }
                }
                if out.mode == .rtp {
                    Stepper("Port \(out.rtpPort)", value: Binding(get: { Int(out.rtpPort) }, set: { out.rtpPort = UInt16($0) }), in: 1024...65535)
                        .frame(width: 160)
                }
                if out.mode == .sidecar {
                    Stepper("Port \(out.sidecarPort)", value: Binding(get: { Int(out.sidecarPort) }, set: { out.sidecarPort = UInt16($0) }), in: 1024...65535)
                        .frame(width: 160)
                    Button(out.sidecarOnline ? "Sidecar: Online" : "Check Sidecar") { out.pingSidecar() }
                        .buttonStyle(.bordered)
                    Button("Refresh Destinations") { out.refreshDestinations() }
                    Button("Sync") { out.fetchRTPStatus(); out.fetchBLEStatus() }
                    if !out.sidecarDestinations.isEmpty {
                        Picker("Destination", selection: $out.selectedDestination) {
                            ForEach(out.sidecarDestinations, id: \.self) { Text($0) }
                        }.frame(width: 240)
                        Button("Select") { out.selectDestination() }
                    }
                    Divider().frame(height: 18)
                    Toggle("RTP", isOn: Binding(get: { out.rtpEnabled }, set: { out.setRTPEnabled($0) }))
                    TextField("RTP host", text: $out.rtpHost).textFieldStyle(.roundedBorder).frame(width: 160)
                    Stepper("Port \(out.rtpConnPort)", value: Binding(get: { Int(out.rtpConnPort) }, set: { out.rtpConnPort = UInt16($0) }), in: 1024...65535)
                    Button("Connect") { out.connectRTP() }
                    Divider().frame(height: 18)
                    TextField("BLE name", text: $out.bleName).textFieldStyle(.roundedBorder).frame(width: 160)
                    Toggle("Advertise", isOn: Binding(get: { out.bleAdvertising }, set: { out.setBLEAdvertising($0) }))
                        .onAppear { out.fetchRTPStatus(); out.fetchBLEStatus() }
                }
                Stepper("Bend ±\(out.bendRange)", value: Binding(get: { Int(out.bendRange) }, set: { out.bendRange = UInt8($0); if out.isOpen { out.close(); out.open() } }), in: 2...96)
                    .frame(width: 160)
                Toggle("Local Audio", isOn: Binding(get: { sine.isRunning }, set: { $0 ? sine.start() : sine.stop() }))
                Toggle(out.isOpen ? "Close" : "Open", isOn: Binding(get: { out.isOpen }, set: { v in if v { out.open() } else { out.close() } }))
                    .toggleStyle(.button)
                if out.mode == .blePeripheral {
                    Toggle("Auto Re-Adv", isOn: $out.autoReAdvertise).frame(width: 120)
                    Button("Re-Advertise") { out.reAdvertiseNow() }
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if out.mode == .sidecar {
                    Text("Sidecar: \(out.sidecarOnline ? "Online" : "Offline") · RTP: \(out.rtpEnabled ? "On" : "Off") · BLE Adv: \(out.bleAdvertising ? "On" : "Off") · Dest: \(out.selectedDestination.isEmpty ? "-" : out.selectedDestination)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in tick &+= 1 }
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                if out.mode == .sidecar && out.sidecarOnline && (tick % 5 == 0) {
                    out.fetchRTPStatus(); out.fetchBLEStatus()
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.12), .purple.opacity(0.12)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .cornerRadius(10)
                    Text("Drag to play — X=pitch, Y=velocity; release resets")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dragging { dragging = true }
                        let nx = max(0, min(1, value.location.x / max(1, w)))
                        let ny = max(0, min(1, 1 - value.location.y / max(1, h)))
                        let vel = MPEPadMapping.velocity(y: ny)
                        let newNote: UInt8 = 60 &+ UInt8((ny * 24).rounded())
                        if newNote != currentNote {
                            out.noteOff(note: currentNote, velocity: 0)
                            currentNote = newNote
                            out.noteOn(note: currentNote, velocity: vel)
                        } else {
                            if !out.isOpen { out.open() }
                            out.noteOn(note: currentNote, velocity: vel)
                        }
                        let pb = MPEPadMapping.pitchBend14(x: nx)
                        out.pitchBend(value14: pb)
                        out.polyAftertouch(note: currentNote, pressure: vel)
                        if sine.isRunning {
                            let deltaSemis = (nx - 0.5) * Double(out.bendRange) * 2.0
                            let freq = 440.0 * pow(2.0, (Double(currentNote) - 69.0 + deltaSemis) / 12.0)
                            sine.set(freq: Float(freq), amp: 0.2)
                        }
                    }
                    .onEnded { _ in
                        dragging = false
                        out.pitchBend(value14: 8192)
                        out.noteOff(note: currentNote, velocity: 0)
                        sine.set(freq: 0, amp: 0)
                    })
            }
            .frame(height: 220)
            .padding(8)
        }
        .frame(minWidth: 720, minHeight: 420)
    }
}

private extension Array {
    func chunked(_ n: Int) -> [[Element]] {
        stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0+n, count)]) }
    }
}
