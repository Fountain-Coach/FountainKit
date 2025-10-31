import Foundation
import MIDI2Transports

public struct UMPEvent: Codable, Sendable {
    var ts: Double
    var words: [UInt32]
    var vendorJSON: String?
    var peJSON: String?
}

@MainActor
final class UmpRecorder {
    private var buf: [UMPEvent] = []
    private let capacity: Int
    private var fh: FileHandle?
    private var logPath: String?
    init(capacity: Int = 2048) { self.capacity = capacity }

    func record(words: [UInt32]) {
        var event = UMPEvent(ts: Date().timeIntervalSince1970, words: words, vendorJSON: nil, peJSON: nil)
        if let vj = decodeVendorJSON(words) { event.vendorJSON = vj }
        else if let pj = decodePENotifyJSON(words) { event.peJSON = pj }
        buf.append(event)
        if buf.count > capacity { buf.removeFirst(buf.count - capacity) }
        write(event)
    }

    func tail(limit: Int) -> [UMPEvent] {
        let n = max(0, min(limit, buf.count))
        return Array(buf.suffix(n))
    }

    func flush() { buf.removeAll(keepingCapacity: true) }

    func recordSnapshot(peJSON: String? = nil, vendorJSON: String? = nil) {
        let ev = UMPEvent(ts: Date().timeIntervalSince1970, words: [], vendorJSON: vendorJSON, peJSON: peJSON)
        buf.append(ev)
        if buf.count > capacity { buf.removeFirst(buf.count - capacity) }
        write(ev)
    }

    private func decodeVendorJSON(_ words: [UInt32]) -> String? {
        let bytes = reassembleSysEx7(words)
        guard bytes.count >= 8, bytes[0] == 0xF0, bytes[1] == 0x7D,
              bytes[2] == 0x4A, bytes[3] == 0x53, bytes[4] == 0x4F, bytes[5] == 0x4E, bytes[6] == 0x00 else { return nil }
        let payload = bytes.dropFirst(7).dropLast(1)
        return String(data: Data(payload), encoding: .utf8)
    }

    private func decodePENotifyJSON(_ words: [UInt32]) -> String? {
        // Expect CI envelope sysEx7 payload: [scope, 0x0D, subId2(0x7C), version, body...]
        let bytes = reassembleSysEx7(words)
        guard bytes.count >= 5, bytes[1] == 0x0D, bytes[2] == 0x7C else { return nil }
        var i = 4
        guard i < bytes.count else { return nil }
        let cmd = bytes[i] & 0x7F; i += 1
        // requestId (7-bit packed x4)
        i += 4
        guard i < bytes.count else { return nil }
        let enc = bytes[i] & 0x7F; i += 1
        guard enc == 0 else { return nil } // json only
        guard i < bytes.count else { return nil }
        let headerLen = Int(bytes[i] & 0x7F); i += 1
        guard i + headerLen <= bytes.count else { return nil }
        i += headerLen
        guard i < bytes.count else { return nil }
        let dataLen = Int(bytes[i] & 0x7F); i += 1
        guard i + dataLen <= bytes.count else { return nil }
        let data7 = Array(bytes[i..<(i+dataLen)])
        let json = Data(data7.map { $0 & 0x7F })
        guard let text = String(data: json, encoding: .utf8) else { return nil }
        // Accept notify (8) or setReply (5) snapshots
        if cmd == 8 || cmd == 5 { return text }
        return nil
    }

    private func reassembleSysEx7(_ words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i + 1 < words.count {
            let w1 = words[i], w2 = words[i+1]
            guard ((w1 >> 28) & 0xF) == 0x3 else { break }
            let count = Int((w1 >> 16) & 0xF)
            let d0 = UInt8((w1 >> 8) & 0xFF)
            let d1 = UInt8(w1 & 0xFF)
            let d2 = UInt8((w2 >> 24) & 0xFF)
            let d3 = UInt8((w2 >> 16) & 0xFF)
            let d4 = UInt8((w2 >> 8) & 0xFF)
            let d5 = UInt8(w2 & 0xFF)
            let chunk = [d0,d1,d2,d3,d4,d5]
            out.append(contentsOf: chunk.prefix(count))
            let status = UInt8((w1 >> 20) & 0xF)
            i += 2
            if status == 0x0 || status == 0x3 { break }
        }
        return out
    }

    // MARK: - File logging (NDJSON)
    func enableFileLog(dirPath: String) {
        let fm = FileManager.default
        do {
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: dirPath, isDirectory: &isDir) {
                try fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
            }
            let ts = Int(Date().timeIntervalSince1970)
            let file = (dirPath as NSString).appendingPathComponent("midi-service-ump-\(ts).ndjson")
            fm.createFile(atPath: file, contents: nil)
            fh = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
            logPath = file
        } catch {
            fh = nil; logPath = nil
        }
    }

    private func write(_ ev: UMPEvent) {
        guard let fh else { return }
        do {
            let data = try JSONEncoder().encode(ev)
            if #available(macOS 13.0, *) {
                try fh.write(contentsOf: data)
                try fh.write(contentsOf: Data("\n".utf8))
            } else {
                fh.write(data)
                fh.write(Data("\n".utf8))
            }
        } catch { /* ignore */ }
    }
}

// MARK: - Headless instruments (co-located for simplicity)
protocol HeadlessInstrument {
    var displayName: String { get }
    func handleVendor(topic: String, data: [String: Any]) -> String?
    func handlePESet(properties: [String: Double]) -> String?
}

@MainActor
final class HeadlessRegistry {
    static let shared = HeadlessRegistry()
    private var byName: [String: any HeadlessInstrument] = [:]
    func register(_ inst: any HeadlessInstrument) { byName[inst.displayName] = inst }
    func unregister(_ name: String) { byName.removeValue(forKey: name) }
    func list() -> [String] { Array(byName.keys).sorted() }
    func resolve(_ name: String?) -> (any HeadlessInstrument)? { guard let name else { return nil }; return byName[name] }
}

final class CanvasHeadlessInstrument: HeadlessInstrument {
    let displayName: String
    private var zoom: Double = 1.0
    private var tx: Double = 0.0
    private var ty: Double = 0.0
    init(displayName: String = "Headless Canvas") { self.displayName = displayName }
    func handleVendor(topic: String, data: [String : Any]) -> String? {
        switch topic {
        case "ui.panBy":
            if let dxDoc = data["dx.doc"] as? Double, let dyDoc = data["dy.doc"] as? Double { tx += dxDoc; ty += dyDoc }
            else if let vx = data["dx.view"] as? Double, let vy = data["dy.view"] as? Double { tx += vx / max(zoom, 1e-6); ty += vy / max(zoom, 1e-6) }
            return snapshot()
        case "ui.zoomAround":
            let ax = (data["anchor.view.x"] as? Double) ?? 0, ay = (data["anchor.view.y"] as? Double) ?? 0
            let magnification = (data["magnification"] as? Double) ?? 0
            let zPrev = zoom; let zNew = max(0.1, min(16.0, zPrev * (1.0 + magnification)))
            let docX = (ax / max(zPrev, 1e-6)) - tx; let docY = (ay / max(zPrev, 1e-6)) - ty
            tx = (ax / max(zNew, 1e-6)) - docX; ty = (ay / max(zNew, 1e-6)) - docY; zoom = zNew
            return snapshot()
        case "canvas.reset": zoom = 1.0; tx = 0.0; ty = 0.0; return snapshot()
        default: return nil
        }
    }
    func handlePESet(properties: [String : Double]) -> String? {
        for (k,v) in properties { switch k { case "zoom": zoom = max(0.1, min(16.0, v)); case "translation.x": tx = v; case "translation.y": ty = v; default: break } }
        return snapshot()
    }
    private func snapshot() -> String? {
        let props: [[String: Any]] = [["name": "zoom", "value": zoom],["name": "translation.x", "value": tx],["name": "translation.y", "value": ty]]
        let obj: [String: Any] = ["properties": props]
        if let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }
}

// MARK: - Fountain Editor (A4 Typewriter) headless instrument
final class FountainEditorHeadlessInstrument: HeadlessInstrument {
    let displayName: String
    // Editor state
    private var content: String = ""
    private var cursor: Int = 0 // UTF-16 index
    // Page + font
    private var pageSize: String = "A4"
    private var marginTopMM: Double = 25
    private var marginLeftMM: Double = 35
    private var marginRightMM: Double = 20
    private var marginBottomMM: Double = 25
    private var fontName: String = "Courier Prime"
    private var fontSizePT: Int = 12
    private var lineHeightEM: Double = 1.10
    // Memory + roles + suggestions
    private var corpusId: String = ""
    private var overlays: [String: Bool] = ["drifts": false, "patterns": false, "reflections": false, "history": false, "arcs": false]
    private var memoryCounts: [String: Int] = ["drifts": 0, "patterns": 0, "reflections": 0, "history": 0, "arcs": 0]
    private var suggestions: [String: (text: String, policy: String, cursor: Int?)] = [:]
    private var rolesEnabled: Bool = true
    private var rolesAvailable: [String] = ["Drift","Patterns","Reflections","History","SemanticArc","ViewCreator"]
    private var rolesActive: String? = nil

    init(displayName: String = "Fountain Editor") { self.displayName = displayName }

    func handleVendor(topic: String, data: [String : Any]) -> String? {
        switch topic {
        case "text.set":
            let t = (data["text"] as? String) ?? ""
            content = t
            if let c = data["cursor"] as? Int { cursor = max(0, min(c, utf16Count(content))) }
            return snapshot()
        case "text.insert":
            let t = (data["text"] as? String) ?? ""
            insertAtCursor(t)
            return snapshot()
        case "text.replace":
            let start = (data["start"] as? Int) ?? cursor
            let end = (data["end"] as? Int) ?? cursor
            let t = (data["text"] as? String) ?? ""
            replaceRange(start: start, end: end, with: t)
            return snapshot()
        case "text.clear":
            content = ""; cursor = 0
            return snapshot()
        case "agent.delta":
            let id = (data["id"] as? String) ?? "agent"
            let t = (data["text"] as? String) ?? ""
            let cur = suggestions[id]?.text ?? ""
            suggestions[id] = (text: cur + t, policy: suggestions[id]?.policy ?? "append", cursor: suggestions[id]?.cursor)
            return snapshot()
        case "agent.suggest":
            guard let id = data["id"] as? String, let t = data["text"] as? String else { return snapshot() }
            let policy = (data["policy"] as? String) ?? "append"
            let c = data["cursor"] as? Int
            suggestions[id] = (text: t, policy: policy, cursor: c)
            return snapshot()
        case "suggestion.apply":
            guard let id = data["id"] as? String, let s = suggestions[id] else { return snapshot() }
            applySuggestion(id: id, suggestion: s)
            suggestions.removeValue(forKey: id)
            return snapshot()
        case "awareness.setCorpus":
            corpusId = (data["corpusId"] as? String) ?? corpusId
            return snapshot(awarenessSynced: true)
        case "awareness.refresh":
            // In headless mode, just acknowledge refresh; counts reflect memory.inject.* calls
            return snapshot(awarenessSynced: true)
        case let s where s.hasPrefix("memory.inject."):
            let kind = String(s.split(separator: ".").last ?? "")
            if var arr = data["items"] as? [[String: Any]] {
                memoryCounts[kind] = arr.count
            } else {
                memoryCounts[kind] = 0
            }
            return snapshot(memoryUpdated: true)
        case "memory.promote":
            // Turn a memory card into a suggestion
            let slot = (data["slot"] as? String) ?? "reflections"
            guard let id = data["id"] as? String else { return snapshot() }
            let policy = (data["policy"] as? String) ?? "append"
            let c = data["cursor"] as? Int
            let text = (data["text"] as? String) ?? ""
            suggestions[id] = (text: text, policy: policy, cursor: c)
            rolesActive = nil
            return snapshot()
        case "role.suggest":
            guard let role = data["role"] as? String, let id = data["id"] as? String, let text = data["text"] as? String else { return snapshot() }
            let policy = (data["policy"] as? String) ?? "append"
            let c = data["cursor"] as? Int
            rolesActive = role
            suggestions[id] = (text: text, policy: policy, cursor: c)
            return snapshot()
        default:
            return nil
        }
    }

    func handlePESet(properties: [String : Double]) -> String? {
        for (k,v) in properties {
            switch k {
            case "cursor.index": cursor = max(0, min(Int(v.rounded()), utf16Count(content)))
            case "page.margins.top": marginTopMM = v
            case "page.margins.left": marginLeftMM = v
            case "page.margins.right": marginRightMM = v
            case "page.margins.bottom": marginBottomMM = v
            case "font.size.pt": fontSizePT = Int(v.rounded())
            case "line.height.em": lineHeightEM = v
            case "overlays.show.drifts": overlays["drifts"] = v >= 0.5
            case "overlays.show.patterns": overlays["patterns"] = v >= 0.5
            case "overlays.show.reflections": overlays["reflections"] = v >= 0.5
            case "overlays.show.history": overlays["history"] = v >= 0.5
            case "overlays.show.arcs": overlays["arcs"] = v >= 0.5
            default: break
            }
        }
        return snapshot()
    }

    // MARK: - Helpers
    private func utf16Count(_ s: String) -> Int { s.utf16.count }
    private func indexAtUTF16(_ s: String, offset: Int) -> String.Index {
        var idx = s.startIndex
        var remaining = max(0, min(offset, s.utf16.count))
        while remaining > 0 && idx < s.endIndex {
            let next = s.index(after: idx)
            let u16 = s[idx..<next].utf16.count
            remaining -= u16
            idx = next
        }
        return idx
    }
    private func insertAtCursor(_ t: String) {
        let idx = indexAtUTF16(content, offset: cursor)
        content.insert(contentsOf: t, at: idx)
        cursor = utf16Count(content)
    }
    private func replaceRange(start: Int, end: Int, with t: String) {
        let i0 = indexAtUTF16(content, offset: min(start, end))
        let i1 = indexAtUTF16(content, offset: max(start, end))
        content.replaceSubrange(i0..<i1, with: t)
        cursor = utf16Count(content)
    }
    private func applySuggestion(id: String, suggestion: (text: String, policy: String, cursor: Int?)) {
        switch suggestion.policy.lowercased() {
        case "insertat":
            if let c = suggestion.cursor { cursor = max(0, min(c, utf16Count(content))) }
            insertAtCursor(suggestion.text)
        case "replace":
            content = suggestion.text
            cursor = utf16Count(content)
        default: // append
            content += suggestion.text
            cursor = utf16Count(content)
        }
    }
    private func wrapColumnEstimate() -> Int {
        // A4 210mm; estimate chars per inch ~10 for Courier 12pt
        let widthIn = 210.0/25.4 - ((marginLeftMM + marginRightMM)/25.4)
        let columns = Int((widthIn * 10.0).rounded())
        return max(40, min(120, columns))
    }
    private func lineCount(_ s: String) -> Int { s.isEmpty ? 0 : s.split(separator: "\n", omittingEmptySubsequences: false).count }
    @MainActor private func snapshot(memoryUpdated: Bool = false, awarenessSynced: Bool = false) -> String? {
        let lines = lineCount(content)
        let chars = utf16Count(content)
        let wrapCol = wrapColumnEstimate()
        var props: [[String: Any]] = []
        func add(_ name: String, _ value: Any) { props.append(["name": name, "value": value]) }
        add("text.content", content)
        add("cursor.index", cursor)
        add("page.size", 0) // R/O label not numeric; skip for numeric PE — included in monitor only
        add("page.margins.top", marginTopMM)
        add("page.margins.left", marginLeftMM)
        add("page.margins.right", marginRightMM)
        add("page.margins.bottom", marginBottomMM)
        add("font.size.pt", fontSizePT)
        add("line.height.em", lineHeightEM)
        add("wrap.column", wrapCol)
        add("suggestions.count", suggestions.count)
        add("memory.counts.drifts", memoryCounts["drifts"] ?? 0)
        add("memory.counts.patterns", memoryCounts["patterns"] ?? 0)
        add("memory.counts.reflections", memoryCounts["reflections"] ?? 0)
        add("memory.counts.history", memoryCounts["history"] ?? 0)
        add("memory.counts.arcs", memoryCounts["arcs"] ?? 0)
        let obj: [String: Any] = [
            "properties": props,
            "meta": [
                "lines": lines,
                "chars": chars,
                "types": [:],
                "page": ["size": pageSize, "margins": ["top": marginTopMM, "left": marginLeftMM, "right": marginRightMM, "bottom": marginBottomMM]],
                "wrapColumn": wrapCol
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) {
            // Also post monitor events: suggestion/memory/awareness events implicit via counts
            if memoryUpdated { SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"memory.slots.updated\"}") }
            if awarenessSynced { SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"awareness.synced\",\"corpusId\":\"\(corpusId)\"}") }
            return s
        }
        return nil
    }
}

enum MIDISendError: Error { case unsupportedTransport, destinationNotFound }

@MainActor
final class SimpleMIDISender {
    #if canImport(CoreMIDI)
    private static var transports: [String: CoreMIDITransport] = [:] // key -> transport
    #endif
    static let recorder = UmpRecorder()
    private static var backend: String = {
        let env = ProcessInfo.processInfo.environment
        if let b = env["MIDI_SERVICE_BACKEND"], !b.isEmpty { return b.lowercased() }
        #if os(macOS)
        return "coremidi"
        #else
        return "alsa"
        #endif
    }()

    static func listDestinationNames() -> [String] {
        var names: [String] = []
        #if canImport(CoreMIDI)
        if backend == "coremidi" { names.append(contentsOf: CoreMIDITransport.destinationNames()) }
        #endif
        if backend == "alsa" { names.append(contentsOf: ALSATransport.availableEndpoints()) }
        names.append(contentsOf: HeadlessRegistry.shared.list())
        return names
    }

    static func send(words: [UInt32], toDisplayName name: String?) async throws {
        // If a headless instrument is registered under the target name, interpret UMP locally
        if let name, let inst = await HeadlessRegistry.shared.resolve(name) as? HeadlessInstrument {
            if let vj = Self.decodeVendorJSON(words) {
                if let body = try? JSONSerialization.jsonObject(with: Data(vj.utf8)) as? [String: Any],
                   let topic = body["topic"] as? String, let data = body["data"] as? [String: Any] {
                    if let snap = inst.handleVendor(topic: topic, data: data) { await recorder.recordSnapshot(peJSON: snap) }
                }
                return
            }
            if let pj = Self.decodePESetJSON(words) {
                if let snap = inst.handlePESet(properties: pj) { await recorder.recordSnapshot(peJSON: snap) }
                return
            }
        }
        #if canImport(CoreMIDI)
        if backend == "coremidi" {
            let key = name ?? "__first__"
            let transport = try ensureCoreMIDITransport(key: key, destinationName: name)
            try transport.send(umpWords: words)
            return
        }
        #endif
        if backend == "alsa" {
            let t = ensureALSATransport()
            try t.send(umpWords: words)
            return
        }
        if backend == "rtp" {
            let t = ensureRTP()
            try t.send(umpWords: words)
            return
        }
        if backend == "loopback" {
            let t = ensureLoopback()
            try t.send(umpWords: words)
            return
        }
        throw MIDISendError.unsupportedTransport
    }

    #if canImport(CoreMIDI)
    private static func ensureCoreMIDITransport(key: String, destinationName: String?) throws -> CoreMIDITransport {
        if let t = transports[key] { return t }
        let t = CoreMIDITransport(name: "midi-service", destinationName: destinationName, enableVirtualEndpoints: false)
        t.onReceiveUMP = { words in Task { await recorder.record(words: words) } }
        try t.open()
        transports[key] = t
        return t
    }

    static func ensureListener() {
        #if canImport(CoreMIDI)
        if backend == "coremidi" { _ = try? ensureCoreMIDITransport(key: "__listener__", destinationName: nil) }
        #endif
    }
    #endif

    // MARK: - UMP decoders (SysEx7)
    private static func reassembleSysEx7(_ words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i + 1 < words.count {
            let w1 = words[i], w2 = words[i+1]
            guard ((w1 >> 28) & 0xF) == 0x3 else { break }
            let count = Int((w1 >> 16) & 0xF)
            let d0 = UInt8((w1 >> 8) & 0xFF)
            let d1 = UInt8(w1 & 0xFF)
            let d2 = UInt8((w2 >> 24) & 0xFF)
            let d3 = UInt8((w2 >> 16) & 0xFF)
            let d4 = UInt8((w2 >> 8) & 0xFF)
            let d5 = UInt8(w2 & 0xFF)
            let chunk = [d0,d1,d2,d3,d4,d5]
            out.append(contentsOf: chunk.prefix(count))
            let status = UInt8((w1 >> 20) & 0xF)
            i += 2
            if status == 0x0 || status == 0x3 { break }
        }
        return out
    }

    static func decodeVendorJSON(_ words: [UInt32]) -> String? {
        let bytes = reassembleSysEx7(words)
        guard bytes.count >= 8, bytes[0] == 0xF0, bytes[1] == 0x7D,
              bytes[2] == 0x4A, bytes[3] == 0x53, bytes[4] == 0x4F, bytes[5] == 0x4E, bytes[6] == 0x00 else { return nil }
        let payload = bytes.dropFirst(7).dropLast(1)
        return String(data: Data(payload), encoding: .utf8)
    }

    static func decodePESetJSON(_ words: [UInt32]) -> [String: Double]? {
        let bytes = reassembleSysEx7(words)
        guard bytes.count >= 5, bytes[1] == 0x0D, bytes[2] == 0x7C else { return nil }
        var i = 4
        guard i < bytes.count else { return nil }
        let cmd = bytes[i] & 0x7F; i += 1
        guard cmd == 4 else { return nil } // set
        i += 4 // requestId
        guard i < bytes.count else { return nil }
        let enc = bytes[i] & 0x7F; i += 1
        guard enc == 0 else { return nil }
        guard i < bytes.count else { return nil }
        let headerLen = Int(bytes[i] & 0x7F); i += 1
        guard i + headerLen <= bytes.count else { return nil }
        i += headerLen
        guard i < bytes.count else { return nil }
        let dataLen = Int(bytes[i] & 0x7F); i += 1
        guard i + dataLen <= bytes.count else { return nil }
        let data7 = Array(bytes[i..<(i+dataLen)])
        let json = Data(data7.map { $0 & 0x7F })
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        var props: [String: Double] = [:]
        if let arr = obj["properties"] as? [[String: Any]] {
            for it in arr { if let name = it["name"] as? String, let v = it["value"] as? Double { props[name] = v } }
        } else {
            for (k, v) in obj { if let d = v as? Double { props[k] = d } }
        }
        return props
    }

    // MARK: - Backends (non-CoreMIDI)
    private static var alsaTransport: ALSATransport?
    private static func ensureALSATransport() -> ALSATransport {
        if let t = alsaTransport { return t }
        let t = ALSATransport(useLoopback: true)
        try? t.open()
        t.onReceiveUMP = { words in Task { await recorder.record(words: words) } }
        alsaTransport = t
        return t
    }

    private static var rtp: RTPMidiSession?
    private static func ensureRTP() -> RTPMidiSession {
        if let t = rtp { return t }
        let t = RTPMidiSession(localName: "midi-service", mtu: 1500, enableDiscovery: false, enableCINegotiation: false)
        try? t.open()
        t.onReceiveUMP = { words in Task { await recorder.record(words: words) } }
        rtp = t
        return t
    }

    private static var loopback: LoopbackTransport?
    private static func ensureLoopback() -> LoopbackTransport {
        if let t = loopback { return t }
        let t = LoopbackTransport()
        try? t.open()
        t.onReceiveUMP = { words in Task { await recorder.record(words: words) } }
        loopback = t
        return t
    }
}

public actor MIDIServiceRuntime {
    public static let shared = MIDIServiceRuntime()
    public func tail(limit: Int) async -> [UMPEvent] { await MainActor.run { SimpleMIDISender.recorder.tail(limit: limit) } }
    public func flush() async { await MainActor.run { SimpleMIDISender.recorder.flush() } }
    public func ensureListener() async { await MainActor.run { SimpleMIDISender.ensureListener() } }
    public func registerHeadlessCanvas(displayName: String = "Headless Canvas") async {
        await HeadlessRegistry.shared.register(CanvasHeadlessInstrument(displayName: displayName))
    }
    public func enableUMPLog(at dirPath: String) async { await MainActor.run { SimpleMIDISender.recorder.enableFileLog(dirPath: dirPath) } }
    public func listHeadless() async -> [String] { await HeadlessRegistry.shared.list() }
    public func registerHeadless(displayName: String, kind: String? = nil) async {
        // For now, only canvas
        await HeadlessRegistry.shared.register(CanvasHeadlessInstrument(displayName: displayName))
    }
    public func unregisterHeadless(displayName: String) async { await HeadlessRegistry.shared.unregister(displayName) }
}
