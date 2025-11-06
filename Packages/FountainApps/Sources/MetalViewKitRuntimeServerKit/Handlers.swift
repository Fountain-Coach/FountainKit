import Foundation
import OpenAPIRuntime
import Foundation
#if os(macOS)
import CoreAudio
#endif
import MetalViewKit

// Shared core state for the runtime
final class MVKRuntimeCore: @unchecked Sendable {
    struct Session { let id: String; var config: Components.Schemas.SessionCreate; var state: String }

    // Sessions
    var sessions: [String: Session] = [:]
    var currentSessionId: String? = nil

    // Clock
    private(set) var testClockEnabled: Bool = false
    private var testClockNs: UInt64 = 0
    private var testClockStart: UInt64 = 0
    private var sysStart: DispatchTime = .now()

    // MIDI events ring (simple)
    private let maxEvents = 10_000
    var midiEvents: [(tNs: UInt64, words: [UInt32])] = []

    // Metrics
    var underruns: Int = 0
    var midiDrops: Int = 0
    var callbackAvgMs: Double = 0
    var callbackP99Ms: Double = 0

    // Fault model (stored only)
    var faultModel: Components.Schemas.FaultModel? = nil

    // Audio backend
    struct AudioBackendState { var backend: Components.Schemas.AudioBackend = .null; var streaming: Bool = false; var deviceId: String? = nil; var sampleRate: Double = 48000; var blockFrames: Int = 128; var channels: Int = 2; var allowFormatFallback: Bool = true }
    var audio = AudioBackendState()

    // Tracing (typed event store)
    private let maxTraces = 10000
    var traces: [Components.Schemas.TraceEvent] = []

    func nowNs() -> UInt64 {
        if testClockEnabled { return testClockNs }
        let elapsed = DispatchTime.now().uptimeNanoseconds - sysStart.uptimeNanoseconds
        return UInt64(elapsed)
    }

    func enableTestClock(startNs: UInt64?) { testClockEnabled = true; if let s = startNs { testClockNs = s } else { testClockNs = nowNs() }; testClockStart = testClockNs }
    func advanceTestClock(deltaNs: UInt64, steps: Int) -> UInt64 { guard testClockEnabled else { return nowNs() }; if steps <= 1 { testClockNs &+= deltaNs; return testClockNs }; let step = deltaNs / UInt64(steps); for _ in 0..<steps { testClockNs &+= step }; return testClockNs }

    func pushEvent(tNs: UInt64, words: [UInt32]) {
        midiEvents.append((tNs, words)); if midiEvents.count > maxEvents { midiEvents.removeFirst(midiEvents.count - maxEvents) }
        let detail: [String: (any Sendable)?] = [
            "words": words.map { String(format: "0x%08X", $0) }
        ]
        let container = try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: detail)
        let ev = Components.Schemas.TraceEvent(_type: "midi.inject", tNs: String(tNs), detail: container)
        recordTrace(ev)
    }

    func recordTrace(_ ev: Components.Schemas.TraceEvent) { traces.append(ev); if traces.count > maxTraces { _ = traces.removeFirst(traces.count - maxTraces) } }
}

final class MVKRuntimeHandlers: APIProtocol, @unchecked Sendable {
    private var endpoints: [String: Components.Schemas.MidiEndpoint] = [:]
    private let core: MVKRuntimeCore
    init(core: MVKRuntimeCore) { self.core = core }
    // Minimal health implementation to get the server compiling; expand alongside handlers.
    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        let uptime = ProcessInfo.processInfo.systemUptime
        return .ok(.init(body: .json(.init(status: .ok, uptimeSec: uptime))))
    }

    // MIDI — inject UMP events (test producer)
    func injectMidiEvents(_ input: Operations.injectMidiEvents.Input) async throws -> Operations.injectMidiEvents.Output {
        guard case let .json(batch) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var frames: [[UInt32]] = []
        let now = core.nowNs()
        for ev in batch.events {
            var words: [UInt32] = []
            let p = ev.packet
            words.append(UInt32(truncatingIfNeeded: p.w0))
            if let w1 = p.w1 { words.append(UInt32(truncatingIfNeeded: w1)) }
            if let w2 = p.w2 { words.append(UInt32(truncatingIfNeeded: w2)) }
            if let w3 = p.w3 { words.append(UInt32(truncatingIfNeeded: w3)) }
            if !words.isEmpty { frames.append(words) }
            core.pushEvent(tNs: now, words: words)
        }
        // Resolve target from query first, then fallback to env/default
        let q = input.query
        _ = MVKBridge.sendBatch(frames,
                                targetDisplayNameSubstring: q.targetDisplayName,
                                targetInstanceId: q.targetInstanceId)
        return .accepted(.init())
    }

    // GET /v1/midi/events — stubbed consumer for tests
    func readMidiEvents(_ input: Operations.readMidiEvents.Input) async throws -> Operations.readMidiEvents.Output {
        var events: [Components.Schemas.MidiEvent] = []
        let since = input.query.sinceNs.flatMap { UInt64($0) } ?? 0
        let lim = input.query.limit ?? 512
        var count = 0
        for (t, w) in core.midiEvents where t >= since {
            if count >= lim { break }
            var pkt = Components.Schemas.UMPPacket(w0: Int(w[0]))
            if w.count > 1 { pkt.w1 = Int(w[1]) }
            if w.count > 2 { pkt.w2 = Int(w[2]) }
            if w.count > 3 { pkt.w3 = Int(w[3]) }
            let ev = Components.Schemas.MidiEvent(tNs: String(t), packet: pkt, sourceEndpointId: nil)
            events.append(ev); count += 1
        }
        let out = Components.Schemas.MidiOutBatch(events: events)
        return .ok(.init(body: .json(out)))
    }

    // POST /v1/midi/vendor — send vendor JSON SysEx7 UMP to target
    func sendVendor(_ input: Operations.sendVendor.Input) async throws -> Operations.sendVendor.Output {
        guard case let .json(body) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let topic = body.topic
        var dict: [String: Any] = [:]
        if let container = body.data {
            if let d = try? JSONEncoder().encode(container),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                dict = obj
            }
        }
        let q = input.query
        // Build words once so we can both emit into out-ring and forward to bridge
        let words = MVKBridge.buildVendorUMP(topic: topic, data: dict)
        core.pushEvent(tNs: core.nowNs(), words: words)
        _ = MVKBridge.sendBatch([words], targetDisplayNameSubstring: q.targetDisplayName, targetInstanceId: q.targetInstanceId)
        return .accepted(.init())
    }

    // Sessions
    func createSession(_ input: Operations.createSession.Input) async throws -> Operations.createSession.Output {
        guard case let .json(cfg) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let id = UUID().uuidString
        core.sessions[id] = .init(id: id, config: cfg, state: "running")
        core.currentSessionId = id
        let s = Components.Schemas.Session(id: id, config: cfg, state: .running)
        return .created(.init(body: .json(s)))
    }
    func getSession(_ input: Operations.getSession.Input) async throws -> Operations.getSession.Output {
        let id = input.path.id
        guard let s = core.sessions[id] else { return .undocumented(statusCode: 404, .init()) }
        let out = Components.Schemas.Session(id: id, config: s.config, state: .init(rawValue: s.state) ?? .running)
        return .ok(.init(body: .json(out)))
    }
    func deleteSession(_ input: Operations.deleteSession.Input) async throws -> Operations.deleteSession.Output {
        let id = input.path.id
        core.sessions.removeValue(forKey: id)
        if core.currentSessionId == id { core.currentSessionId = nil }
        return .noContent
    }

    // Clock
    func getClock(_ input: Operations.getClock.Input) async throws -> Operations.getClock.Output {
        let now = core.nowNs()
        let mode: Components.Schemas.ClockNow.modePayload = core.testClockEnabled ? .test : .system
        return .ok(.init(body: .json(.init(nowNs: String(now), mode: mode))))
    }
    func enableTestClock(_ input: Operations.enableTestClock.Input) async throws -> Operations.enableTestClock.Output {
        var start: UInt64? = nil
        if case let .json(b) = input.body, let s = b.startNs, let val = UInt64(s) { start = val }
        core.enableTestClock(startNs: start)
        return .noContent
    }
    func advanceTestClock(_ input: Operations.advanceTestClock.Input) async throws -> Operations.advanceTestClock.Output {
        guard case let .json(b) = input.body, let d = UInt64(b.deltaNs) else { return .undocumented(statusCode: 400, .init()) }
        let steps = max(1, b.steps ?? 1)
        let t = core.advanceTestClock(deltaNs: d, steps: steps)
        return .ok(.init(body: .json(.init(nowNs: String(t), mode: .test))))
    }

    // Audio render (headless)
    func renderAudio(_ input: Operations.renderAudio.Input) async throws -> Operations.renderAudio.Output {
        guard case let .json(b) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let frames = b.frames
        let channels = (b.channels?.rawValue) ?? 2
        let rate = b.sampleRate ?? 48000
        // Generate a short sine at 440 Hz across frames (mono duplicated to channels)
        var pcm: [Double] = []
        pcm.reserveCapacity(frames * channels)
        for i in 0..<frames {
            let t = Double(i) / Double(rate)
            let s = sin(2.0 * Double.pi * 440.0 * t) * 0.1
            for _ in 0..<channels { pcm.append(s) }
        }
        let resp = Components.Schemas.AudioRenderResponse(pcm: pcm.map(Float.init), frames: frames, channels: channels, sampleRate: rate)
        return .ok(.init(body: .json(resp)))
    }

    // Video tick
    func videoTick(_ input: Operations.videoTick.Input) async throws -> Operations.videoTick.Output { return .noContent }

    // Fault model
    func setFaultModel(_ input: Operations.setFaultModel.Input) async throws -> Operations.setFaultModel.Output { if case let .json(m) = input.body { core.faultModel = m }; return .noContent }

    // Test scenario (no-op loader)
    func loadTestScenario(_ input: Operations.loadTestScenario.Input) async throws -> Operations.loadTestScenario.Output {
        guard case let .json(scen) = input.body else { return .undocumented(statusCode: 400, .init()) }
        // Execute steps sequentially; recognized ops: advanceClock, injectUMP, sendVendor, sleepMs
        for container in scen.steps ?? [] {
            guard let data = try? JSONEncoder().encode(container),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let op = (obj["op"] as? String) ?? ""
            switch op {
            case "advanceClock":
                if let d = obj["deltaNs"] as? String, let val = UInt64(d) { _ = core.advanceTestClock(deltaNs: val, steps: Int(obj["steps"] as? Double ?? 1)) }
            case "injectUMP":
                if let arr = obj["words"] as? [Any] {
                    let words = arr.compactMap { v -> UInt32? in
                        if let s = v as? String, s.hasPrefix("0x"), let n = UInt32(s, radix: 16) { return n }
                        if let i = v as? Int { return UInt32(truncatingIfNeeded: i) }
                        return nil
                    }
                    if !words.isEmpty { core.pushEvent(tNs: core.nowNs(), words: words); _ = MVKBridge.sendBatch([words]) }
                }
            case "sendVendor":
                let topic = (obj["topic"] as? String) ?? ""
                let data = (obj["data"] as? [String: Any]) ?? [:]
                _ = MVKBridge.sendVendorJSON(topic: topic, data: data)
            case "sleepMs":
                let ms = Int((obj["ms"] as? Double) ?? 0)
                if ms > 0 { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
            default:
                continue
            }
        }
        return .noContent
    }

    // Metrics
    func getMetrics(_ input: Operations.getMetrics.Input) async throws -> Operations.getMetrics.Output {
        let m = Components.Schemas.Metrics(underruns: core.underruns, midiDrops: core.midiDrops, callbackAvgMs: core.callbackAvgMs, callbackP99Ms: core.callbackP99Ms)
        return .ok(.init(body: .json(m)))
    }

    // Tracing
    func tracingDump(_ input: Operations.tracingDump.Input) async throws -> Operations.tracingDump.Output { return .ok(.init(body: .json(core.traces))) }
    func tracingStream(_ input: Operations.tracingStream.Input) async throws -> Operations.tracingStream.Output { return .undocumented(statusCode: 400, .init()) }

    // Audio backend
    func getAudioBackendStatus(_ input: Operations.getAudioBackendStatus.Input) async throws -> Operations.getAudioBackendStatus.Output {
        let s = core.audio
        let st = Components.Schemas.AudioBackendStatus(backend: s.backend, streaming: s.streaming, deviceId: s.deviceId, sampleRate: Float(s.sampleRate), blockFrames: s.blockFrames)
        return .ok(.init(body: .json(st)))
    }
    func patchAudioBackendPolicy(_ input: Operations.patchAudioBackendPolicy.Input) async throws -> Operations.patchAudioBackendPolicy.Output {
        guard case let .json(p) = input.body else { return .undocumented(statusCode: 400, .init()) }
        if let pref = p.preferredBackend { core.audio.backend = pref }
        core.audio.allowFormatFallback = p.allowFormatFallback ?? true
        return .noContent
    }
    func listAudioDevices(_ input: Operations.listAudioDevices.Input) async throws -> Operations.listAudioDevices.Output {
        let scope: String = {
            if let v = input.query.scope { return v.rawValue }
            return "output"
        }()
        var devices: [Components.Schemas.AudioDeviceInfo] = []
        // Try system enumeration; fall back to a synthetic device
        let listed = AudioDeviceEnumerator.list(scope: scope)
        for d in listed {
            let rates = d.rates.map { Float($0) }
            let dev = Components.Schemas.AudioDeviceInfo(id: d.id, name: d.name, rates: rates, blockSizes: d.blockSizes, latencyMs: d.latencyMs)
            devices.append(dev)
        }
        if devices.isEmpty {
            devices.append(.init(id: "null-default", name: "Null Output", rates: [48000, 44100], blockSizes: [64, 96, 128, 256, 512], latencyMs: 10))
        }
        return .ok(.init(body: .json(devices)))
    }
    func openAudioDevice(_ input: Operations.openAudioDevice.Input) async throws -> Operations.openAudioDevice.Output {
        guard case let .json(n) = input.body else { return .undocumented(statusCode: 400, .init()) }
        core.audio.deviceId = input.path.id
        var desiredSR = n.desiredSampleRate.map(Double.init)
        var desiredBF = n.desiredBlockFrames
        let allowFB = n.allowFormatFallback ?? core.audio.allowFormatFallback

        if let id = core.audio.deviceId {
            if let info = AudioDeviceEnumerator.get(id: id) {
                // Negotiate sample rate
                if let d = desiredSR {
                    if !info.rates.contains(d) {
                        if allowFB, let nearest = info.rates.min(by: { abs($0 - d) < abs($1 - d) }) {
                            desiredSR = nearest
                        } else {
                            return .undocumented(statusCode: 400, .init())
                        }
                    }
                } else {
                    desiredSR = info.rates.first
                }
                // Negotiate block frames
                if let b = desiredBF {
                    if !info.blockSizes.contains(b) {
                        if allowFB, let nb = info.blockSizes.min(by: { abs($0 - b) < abs($1 - b) }) {
                            desiredBF = nb
                        } else {
                            return .undocumented(statusCode: 400, .init())
                        }
                    }
                } else {
                    desiredBF = info.blockSizes.first
                }
            } else {
                // Unknown device id: keep requested or defaults
            }
        }

        if let sr = desiredSR { core.audio.sampleRate = sr }
        if let bf = desiredBF { core.audio.blockFrames = bf }
        if let ch = n.channels { core.audio.channels = ch.rawValue }
        let cfg = Components.Schemas.StreamConfig(deviceId: core.audio.deviceId, sampleRate: Float(core.audio.sampleRate), blockFrames: core.audio.blockFrames, channels: core.audio.channels)
        return .ok(.init(body: .json(cfg)))
    }
    func startAudioStream(_ input: Operations.startAudioStream.Input) async throws -> Operations.startAudioStream.Output {
        core.audio.streaming = true
        // Trace event
        // Trace minimal event (detail omitted for strict Sendable safety)
        core.recordTrace(.init(_type: "audio.stream.started", tNs: String(core.nowNs()), detail: nil))
        return .noContent
    }
    func stopAudioStream(_ input: Operations.stopAudioStream.Input) async throws -> Operations.stopAudioStream.Output { core.audio.streaming = false; return .noContent }
    func getAudioStreamStats(_ input: Operations.getAudioStreamStats.Input) async throws -> Operations.getAudioStreamStats.Output {
        let st = Components.Schemas.IOStats(callbacks: 0, underruns: core.underruns, avgMs: core.callbackAvgMs, p99Ms: core.callbackP99Ms)
        return .ok(.init(body: .json(st)))
    }
    func audioBackendEvents(_ input: Operations.audioBackendEvents.Input) async throws -> Operations.audioBackendEvents.Output { return .undocumented(statusCode: 400, .init()) }

    // MIDI endpoints — in-memory runtime endpoints
    func listMidiEndpoints(_ input: Operations.listMidiEndpoints.Input) async throws -> Operations.listMidiEndpoints.Output {
        var list: [Components.Schemas.MidiEndpoint] = []
        // In-memory endpoints
        list.append(contentsOf: endpoints.values)
        // Live Loopback instruments (if present)
        let live = LoopbackMetalInstrumentTransport.shared.listDescriptors()
        for d in live {
            let create = Components.Schemas.MidiEndpointCreate(name: d.displayName,
                                                               direction: .input,
                                                               groups: 1,
                                                               jrTimestampSupport: true)
            let idwrap = Components.Schemas.MidiEndpoint.Value2Payload(id: d.instanceId)
            let ep = Components.Schemas.MidiEndpoint(value1: create, value2: idwrap)
            list.append(ep)
        }
        return .ok(.init(body: .json(list)))
    }

    func createMidiEndpoint(_ input: Operations.createMidiEndpoint.Input) async throws -> Operations.createMidiEndpoint.Output {
        guard case let .json(body) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let id = UUID().uuidString
        let ep = Components.Schemas.MidiEndpoint(
            value1: body,
            value2: .init(id: id)
        )
        endpoints[id] = ep
        return .created(.init(body: .json(ep)))
    }
}

// MARK: - System Audio Device Enumeration (macOS only)
struct AudioDeviceEnumerator {
    struct Info { let id: String, name: String, rates: [Double], blockSizes: [Int], latencyMs: Double }
    static func list(scope: String) -> [Info] {
        #if os(macOS)
        return listMac(scope: scope)
        #else
        return []
        #endif
    }
    static func get(id: String) -> Info? {
        #if os(macOS)
        if id == "null-default" { return .init(id: id, name: "Null Output", rates: [48000, 44100], blockSizes: [64,96,128,256,512], latencyMs: 10) }
        return list(scope: "output").first { $0.id == id }
        #else
        if id == "null-default" { return .init(id: id, name: "Null Output", rates: [48000, 44100], blockSizes: [64,96,128,256,512], latencyMs: 10) }
        return nil
        #endif
    }

    #if os(macOS)
    private static func listMac(scope: String) -> [Info] {
        var out: [Info] = []
        let wantOutput = scope == "output" || scope == "duplex"
        let wantInput = scope == "input" || scope == "duplex"
        for dev in allDeviceIDs() {
            let hasOut = streamsCount(dev, isOutput: true) > 0
            let hasIn = streamsCount(dev, isOutput: false) > 0
            if scope == "output" && !hasOut { continue }
            if scope == "input" && !hasIn { continue }
            if scope == "duplex" && !(hasOut && hasIn) { continue }
            let uid = deviceUID(dev) ?? String(dev)
            let name = deviceName(dev) ?? "Device#\(uid)"
            // Prefer output sample rate for calc
            let sr = deviceNominalSampleRate(dev) ?? 48000
            let rates = availableNominalSampleRates(dev) ?? [sr]
            let range = bufferFrameSizeRange(dev)
            let typical: [Int] = [32, 64, 96, 128, 256, 512, 1024, 2048]
            let blocks = typical.filter { v in
                if let r = range { return v >= Int(r.mMinimum) && v <= Int(r.mMaximum) }
                return true
            }
            // Latency: take max of input/output if duplex requested, else pick according to scope
            let latOut = deviceLatency(dev, isOutput: true) ?? 0
            let latIn = deviceLatency(dev, isOutput: false) ?? 0
            let latFrames: UInt32 = scope == "input" ? latIn : (scope == "output" ? latOut : max(latOut, latIn))
            let latencyMs = (Double(latFrames) / sr) * 1000.0
            out.append(.init(id: uid, name: name, rates: rates, blockSizes: blocks, latencyMs: latencyMs))
        }
        return out
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = Array(repeating: AudioObjectID(0), count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        guard status == noErr else { return [] }
        return ids.filter { $0 != 0 }
    }

    private static func streamsCount(_ device: AudioObjectID, isOutput: Bool) -> Int {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: isOutput ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size)
        guard status == noErr else { return 0 }
        let count = Int(size) / MemoryLayout<AudioStreamID>.size
        return count
    }

    private static func deviceName(_ device: AudioObjectID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        return status == noErr ? (name as String) : nil
    }

    private static func deviceUID(_ device: AudioObjectID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        return status == noErr ? (uid as String) : nil
    }

    private static func deviceNominalSampleRate(_ device: AudioObjectID) -> Double? {
        var rate = Double(0)
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)
        return status == noErr ? rate : nil
    }

    private static func availableNominalSampleRates(_ device: AudioObjectID) -> [Double]? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return nil }
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = Array(repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &ranges)
        guard status == noErr else { return nil }
        var rates: [Double] = []
        for r in ranges {
            // Include both min and max if reasonable
            if r.mMinimum >= 8000, r.mMinimum <= 192000 { rates.append(r.mMinimum) }
            if r.mMaximum != r.mMinimum, r.mMaximum <= 192000 { rates.append(r.mMaximum) }
        }
        return Array(Set(rates)).sorted()
    }

    private static func bufferFrameSizeRange(_ device: AudioObjectID) -> AudioValueRange? {
        var range = AudioValueRange(mMinimum: 0, mMaximum: 0)
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSizeRange,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &range)
        return status == noErr ? range : nil
    }

    private static func deviceLatency(_ device: AudioObjectID, isOutput: Bool) -> UInt32? {
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyLatency,
                                                 mScope: isOutput ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &frames)
        return status == noErr ? frames : nil
    }
    #endif
}
