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
@MainActor
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
@MainActor
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
    private var parseAuto: Bool = true
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
            // Emit monitor that a suggestion was queued from agent
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"suggestion.queued\",\"id\":\"\(id)\",\"source\":\"agent\",\"policy\":\"\(policy)\",\"len\":\(t.count)}")
            return snapshot()
        case "suggestion.apply":
            guard let id = data["id"] as? String, let s = suggestions[id] else { return snapshot() }
            applySuggestion(id: id, suggestion: s)
            suggestions.removeValue(forKey: id)
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"suggestion.applied\",\"id\":\"\(id)\"}")
            return snapshot()
        case "awareness.setCorpus":
            corpusId = (data["corpusId"] as? String) ?? corpusId
            return snapshot(awarenessSynced: true)
        case "awareness.refresh":
            // In headless mode, just acknowledge refresh; counts reflect memory.inject.* calls
            return snapshot(awarenessSynced: true)
        case let s where s.hasPrefix("memory.inject."):
            let kind = String(s.split(separator: ".").last ?? "")
            if let arr = data["items"] as? [[String: Any]] {
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
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"suggestion.queued\",\"id\":\"\(id)\",\"source\":\"memory:\(slot)\",\"policy\":\"\(policy)\",\"len\":\(text.count)}")
            rolesActive = nil
            return snapshot()
        case "role.suggest":
            guard let role = data["role"] as? String, let id = data["id"] as? String, let text = data["text"] as? String else { return snapshot() }
            let policy = (data["policy"] as? String) ?? "append"
            let c = data["cursor"] as? Int
            rolesActive = role
            suggestions[id] = (text: text, policy: policy, cursor: c)
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"suggestion.queued\",\"id\":\"\(id)\",\"source\":\"role:\(role)\",\"policy\":\"\(policy)\",\"len\":\(text.count)}")
            return snapshot()
        case "editor.submit":
            // Prefer routing through Flow instrument when present; fallback to Corpus.
            let submittedText = (data["text"] as? String) ?? content
            let normalized: String = {
                var s = submittedText
                s = s.replacingOccurrences(of: "\t", with: "    ")
                if !s.hasSuffix("\n") { s.append("\n") }
                return s
            }()
            if let flow = HeadlessRegistry.shared.resolve("Flow") as? FlowHeadlessInstrument {
                let from: [String: Any] = ["node": "Fountain Editor", "port": "text.content.out"]
                let payload: [String: Any] = ["kind": "text", "text": normalized]
                _ = flow.handleVendor(topic: "flow.forward.test", data: ["from": from, "payload": payload])
            } else if let corpusInst = HeadlessRegistry.shared.resolve("Corpus Instrument") as? CorpusHeadlessInstrument {
                let payload: [String: Any] = [
                    "text": normalized,
                    "pageId": "store://prompt/fountain-editor",
                    "baselineId": "b-\(Int(Date().timeIntervalSince1970))",
                    "corpusId": corpusId
                ]
                _ = corpusInst.handleVendor(topic: "corpus.baseline.add", data: payload)
            }
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"editor.submitted\",\"corpusId\":\"\(corpusId)\"}")
            return snapshot()
        default:
            return nil
        }
    }

    func handlePESet(properties: [String : Double]) -> String? {
        var parseRequested = false
        for (k,v) in properties {
            switch k {
            case "cursor.index": cursor = max(0, min(Int(v.rounded()), utf16Count(content)))
            case "page.margins.top": marginTopMM = v
            case "page.margins.left": marginLeftMM = v
            case "page.margins.right": marginRightMM = v
            case "page.margins.bottom": marginBottomMM = v
            case "font.size.pt": fontSizePT = Int(v.rounded())
            case "line.height.em": lineHeightEM = v
            case "parse.auto": parseAuto = v >= 0.5
            case "roles.enabled": rolesEnabled = v >= 0.5
            case "overlays.show.drifts": overlays["drifts"] = v >= 0.5
            case "overlays.show.patterns": overlays["patterns"] = v >= 0.5
            case "overlays.show.reflections": overlays["reflections"] = v >= 0.5
            case "overlays.show.history": overlays["history"] = v >= 0.5
            case "overlays.show.arcs": overlays["arcs"] = v >= 0.5
            case "parse.snapshot": parseRequested = v >= 0.5
            default: break
            }
        }
        return snapshot(textParsed: parseRequested)
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
    @MainActor private func snapshot(memoryUpdated: Bool = false, awarenessSynced: Bool = false, textParsed: Bool = false) -> String? {
        let lines = lineCount(content)
        let chars = utf16Count(content)
        let wrapCol = wrapColumnEstimate()
        var props: [[String: Any]] = []
        func add(_ name: String, _ value: Any) { props.append(["name": name, "value": value]) }
        add("text.content", content)
        add("cursor.index", cursor)
        add("page.size", pageSize)
        add("page.margins.top", marginTopMM)
        add("page.margins.left", marginLeftMM)
        add("page.margins.right", marginRightMM)
        add("page.margins.bottom", marginBottomMM)
        add("font.name", fontName)
        add("font.size.pt", fontSizePT)
        add("line.height.em", lineHeightEM)
        add("parse.auto", parseAuto ? 1 : 0)
        add("awareness.corpusId", corpusId)
        add("wrap.column", wrapCol)
        add("suggestions.count", suggestions.count)
        add("suggestions.active.id", "")
        add("roles.enabled", rolesEnabled ? 1 : 0)
        add("roles.available", rolesAvailable)
        add("roles.active", rolesActive ?? "")
        add("overlays.show.drifts", overlays["drifts"] == true ? 1 : 0)
        add("overlays.show.patterns", overlays["patterns"] == true ? 1 : 0)
        add("overlays.show.reflections", overlays["reflections"] == true ? 1 : 0)
        add("overlays.show.history", overlays["history"] == true ? 1 : 0)
        add("overlays.show.arcs", overlays["arcs"] == true ? 1 : 0)
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
            // Post a text.parsed monitor event (used by MRTS to assert counts)
            let meta = "\\\"lines\\\":\(lines),\\\"chars\\\":\(chars),\\\"wrapColumn\\\":\(wrapCol),\\\"page\\\":{\\\"size\\\":\\\"\(pageSize)\\\",\\\"margins\\\":{\\\"top\\\":\(marginTopMM),\\\"left\\\":\(marginLeftMM),\\\"right\\\":\(marginRightMM),\\\"bottom\\\":\(marginBottomMM)}}"
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"text.parsed\",\(meta)}")
            return s
        }
        return nil
    }
}

// MARK: - Corpus Instrument headless
@MainActor
final class CorpusHeadlessInstrument: HeadlessInstrument {
    let displayName: String
    // Active context/state
    private var corpusId: String = "baseline-patchbay"
    private var pageId: String = ""
    private var baselineLatestId: String = ""
    private var driftLatestId: String = ""
    private var patternsLatestId: String = ""
    private var reflectionLatestId: String = ""
    private var lastOp: String = ""
    private var lastTs: String = ""
    private var baselinesTotal: Int = 0
    private var analysesTotal: Int = 0

    init(displayName: String = "Corpus Instrument") { self.displayName = displayName }

    func handleVendor(topic: String, data: [String : Any]) -> String? {
        let nowISO: String = {
            let f = ISO8601DateFormatter(); return f.string(from: Date())
        }()
        switch topic {
        case "editor.submit":
            // Treat as baseline.add with normalisation handled by caller/editor.
            let text = (data["text"] as? String) ?? ""
            let pid = (data["pageId"] as? String) ?? pageId
            let bid = (data["baselineId"] as? String) ?? "b-\(Int(Date().timeIntervalSince1970))"
            pageId = pid
            baselineLatestId = bid
            lastOp = "baseline.add"; lastTs = nowISO
            baselinesTotal += 1
            let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"corpus.baseline.added\",\"corpusId\":\"\(corpusId)\",\"baselineId\":\"\(bid)\",\"lines\":\(lines),\"chars\":\(text.utf16.count)}")
            return snapshot()
        case "corpus.baseline.add":
            let text = (data["text"] as? String) ?? ""
            if let cid = data["corpusId"] as? String { corpusId = cid }
            if let pid = data["pageId"] as? String { pageId = pid }
            let bid = (data["baselineId"] as? String) ?? "b-\(Int(Date().timeIntervalSince1970))"
            baselineLatestId = bid
            lastOp = "baseline.add"; lastTs = nowISO
            baselinesTotal += 1
            let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"corpus.baseline.added\",\"corpusId\":\"\(corpusId)\",\"baselineId\":\"\(bid)\",\"lines\":\(lines),\"chars\":\(text.utf16.count)}")
            return snapshot()
        case "corpus.drift.compute":
            driftLatestId = "d-\(Int(Date().timeIntervalSince1970))"
            lastOp = "drift.compute"; lastTs = nowISO
            analysesTotal += 1
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"corpus.drift.computed\",\"added\":1,\"changed\":0,\"removed\":0}")
            return snapshot()
        case "corpus.patterns.compute":
            patternsLatestId = "p-\(Int(Date().timeIntervalSince1970))"
            lastOp = "patterns.compute"; lastTs = nowISO
            analysesTotal += 1
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"corpus.patterns.computed\",\"count\":3}")
            return snapshot()
        case "corpus.reflection.compute":
            reflectionLatestId = "r-\(Int(Date().timeIntervalSince1970))"
            lastOp = "reflection.compute"; lastTs = nowISO
            analysesTotal += 1
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"corpus.reflection.computed\",\"claims\":5}")
            return snapshot()
        case "corpus.analysis.index":
            analysesTotal += 1
            lastOp = "analysis.index"; lastTs = nowISO
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"corpus.analysis.indexed\",\"pageId\":\"\(pageId)\"}")
            return snapshot()
        case "corpus.page.upsert":
            if let pid = data["pageId"] as? String { pageId = pid }
            lastOp = "page.upsert"; lastTs = nowISO
            return snapshot()
        default:
            return nil
        }
    }

    func handlePESet(properties: [String : Double]) -> String? {
        // Accept corpus.id/page.id set via PE (string -> Double not directly supported by decoder; use vendor where needed)
        return snapshot()
    }

    private func snapshot() -> String? {
        var props: [[String: Any]] = []
        func add(_ name: String, _ value: Any) { props.append(["name": name, "value": value]) }
        add("corpus.id", corpusId)
        add("page.id", pageId)
        add("baseline.latest.id", baselineLatestId)
        add("drift.latest.id", driftLatestId)
        add("patterns.latest.id", patternsLatestId)
        add("reflection.latest.id", reflectionLatestId)
        add("last.op", lastOp)
        add("last.ts", lastTs)
        add("baselines.total", baselinesTotal)
        add("analyses.total", analysesTotal)
        let obj: [String: Any] = ["properties": props]
        if let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }
}

// MARK: - Flow Instrument (typed graph + routing)
@MainActor
final class FlowHeadlessInstrument: HeadlessInstrument {
    struct Port: Hashable { let id: String; let dir: String; let kind: String }
    struct Node { var id: String; var displayName: String; var product: String; var ports: [Port] }
    struct Edge { var id: String; var fromNode: String; var fromPort: String; var toNode: String; var toPort: String; var transformId: String? }

    let displayName: String
    private var nodes: [String: Node] = [:]
    private var edges: [Edge] = []
    private var routingEnabled: Bool = true
    private var selectedNodeId: String? = nil
    private var selectedEdgeId: String? = nil

    init(displayName: String = "Flow") { self.displayName = displayName }

    func handleVendor(topic: String, data: [String : Any]) -> String? {
        switch topic {
        case "flow.node.add":
            guard let nodeId = data["nodeId"] as? String,
                  let displayName = data["displayName"] as? String,
                  let product = data["product"] as? String else { return snapshot() }
            var node = Node(id: nodeId, displayName: displayName, product: product, ports: [])
            // Auto ports for known products
            switch product.lowercased() {
            case "fountaineditor":
                node.ports.append(contentsOf:[Port(id: "text.parsed.out", dir: "out", kind: "text"), Port(id: "text.content.out", dir: "out", kind: "text")])
            case "corpusinstrument":
                node.ports.append(contentsOf:[
                    Port(id: "editor.submit.in", dir: "in", kind: "text"),
                    Port(id: "baseline.add.in", dir: "in", kind: "baseline"),
                    Port(id: "drift.compute.in", dir: "in", kind: "baseline"),
                    Port(id: "patterns.compute.in", dir: "in", kind: "drift"),
                    Port(id: "reflection.compute.in", dir: "in", kind: "patterns"),
                    Port(id: "baseline.added.out", dir: "out", kind: "baseline"),
                    Port(id: "drift.computed.out", dir: "out", kind: "drift"),
                    Port(id: "patterns.computed.out", dir: "out", kind: "patterns"),
                    Port(id: "reflection.computed.out", dir: "out", kind: "reflection")
                ])
            case "submit":
                node.ports.append(contentsOf:[Port(id: "in", dir: "in", kind: "text"), Port(id: "out", dir: "out", kind: "baseline")])
            case "computedrift":
                node.ports.append(contentsOf:[Port(id: "in", dir: "in", kind: "baseline"), Port(id: "out", dir: "out", kind: "drift")])
            case "computepatterns":
                node.ports.append(contentsOf:[Port(id: "in", dir: "in", kind: "drift"), Port(id: "out", dir: "out", kind: "patterns")])
            case "computereflection":
                node.ports.append(contentsOf:[Port(id: "in", dir: "in", kind: "patterns"), Port(id: "out", dir: "out", kind: "reflection")])
            case "llmadapter":
                node.ports.append(contentsOf:[
                    Port(id: "prompt.in", dir: "in", kind: "text"),
                    Port(id: "messages.in", dir: "in", kind: "json"),
                    Port(id: "tool.result.in", dir: "in", kind: "json"),
                    Port(id: "answer.out", dir: "out", kind: "text"),
                    Port(id: "function.call.out", dir: "out", kind: "json")
                ])
            default: break
            }
            nodes[nodeId] = node
            return snapshot()
        case "flow.node.remove":
            if let nodeId = data["nodeId"] as? String { nodes.removeValue(forKey: nodeId); edges.removeAll { $0.fromNode == nodeId || $0.toNode == nodeId } }
            return snapshot()
        case "flow.port.define":
            guard let nodeId = data["nodeId"] as? String, var node = nodes[nodeId],
                  let portId = data["portId"] as? String, let dir = data["dir"] as? String, let kind = data["kind"] as? String else { return snapshot() }
            node.ports.append(Port(id: portId, dir: dir, kind: kind)); nodes[nodeId] = node
            return snapshot()
        case "flow.edge.create":
            guard let from = data["from"] as? [String: Any], let to = data["to"] as? [String: Any],
                  let fn = from["node"] as? String, let fp = from["port"] as? String,
                  let tn = to["node"] as? String, let tp = to["port"] as? String else { return snapshot() }
            let id = data["edgeId"] as? String ?? "e-\(edges.count+1)"
            let edge = Edge(id: id, fromNode: fn, fromPort: fp, toNode: tn, toPort: tp, transformId: data["transformId"] as? String)
            if isCompatible(edge: edge) {
                edges.append(edge)
                SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"flow.edge.created\",\"id\":\"\(id)\"}")
            }
            return snapshot()
        case "flow.edge.delete":
            if let id = data["edgeId"] as? String { edges.removeAll { $0.id == id }; SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"flow.edge.deleted\",\"id\":\"\(id)\"}") }
            return snapshot()
        case "flow.forward.test":
            guard routingEnabled else { return snapshot() }
            guard let from = data["from"] as? [String: Any], var fn = from["node"] as? String, let fp = from["port"] as? String else { return snapshot() }
            let payload = data["payload"] as? [String: Any] ?? [:]
            // Accept either node.id or displayName
            if !nodes.keys.contains(fn) {
                if let match = nodes.values.first(where: { $0.displayName == fn }) { fn = match.id }
            }
            let outEdges = edges.filter { $0.fromNode == fn && $0.fromPort == fp }
            var forwarded = 0
            for e in outEdges { forwarded += route(edge: e, payload: payload) }
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"flow.forwarded\",\"count\":\(forwarded)}")
            return snapshot()
        default:
            return nil
        }
    }

    func handlePESet(properties: [String : Double]) -> String? {
        for (k,v) in properties { if k == "routing.enabled" { routingEnabled = v >= 0.5 } }
        return snapshot()
    }

    private func isCompatible(edge: Edge) -> Bool {
        guard let out = nodes[edge.fromNode]?.ports.first(where: { $0.id == edge.fromPort && $0.dir == "out" }),
              let inn = nodes[edge.toNode]?.ports.first(where: { $0.id == edge.toPort && $0.dir == "in" }) else { return false }
        if out.kind == inn.kind { return true }
        // Coercions via transform nodes - allow text→baseline via Submit
        if let t = edge.transformId, let prod = nodes[t]?.product.lowercased() {
            if prod == "submit" && out.kind == "text" && inn.kind == "baseline" { return true }
        }
        return false
    }

    private func route(edge: Edge, payload: [String: Any]) -> Int {
        // If transform is a Submit, convert text→baseline by invoking Corpus
        if let t = edge.transformId, let prod = nodes[t]?.product.lowercased(), prod == "submit" {
            if let corpus = HeadlessRegistry.shared.resolve("Corpus Instrument") as? CorpusHeadlessInstrument {
                let text = (payload["text"] as? String) ?? ""
                let body: [String: Any] = ["text": text]
                _ = corpus.handleVendor(topic: "corpus.baseline.add", data: body)
                return 1
            }
            return 0
        }
        // Direct port-to-port: for now, only handle baseline.add.in on Corpus
        if let target = nodes[edge.toNode], target.product.lowercased() == "corpusinstrument" {
            if let corpus = HeadlessRegistry.shared.resolve("Corpus Instrument") as? CorpusHeadlessInstrument {
                if edge.toPort == "baseline.add.in" {
                    let text = (payload["text"] as? String) ?? ""
                    _ = corpus.handleVendor(topic: "corpus.baseline.add", data: ["text": text])
                    return 1
                }
            }
        }
        return 0
    }

    private func snapshot() -> String? {
        var props: [[String: Any]] = []
        func add(_ name: String, _ value: Any) { props.append(["name": name, "value": value]) }
        let nodeArr: [[String: Any]] = nodes.values.sorted { $0.id < $1.id }.map { n in
            ["id": n.id, "displayName": n.displayName, "product": n.product,
             "ports": n.ports.map { ["id": $0.id, "dir": $0.dir, "kind": $0.kind] }]
        }
        let edgeArr: [[String: Any]] = edges.map { e in
            var obj: [String: Any] = [
                "id": e.id,
                "from": ["node": e.fromNode, "port": e.fromPort],
                "to": ["node": e.toNode, "port": e.toPort]
            ]
            if let t = e.transformId { obj["transformId"] = t }
            return obj
        }
        add("flow.nodes", nodeArr)
        add("flow.edges", edgeArr)
        add("selected.nodeId", selectedNodeId ?? "")
        add("selected.edgeId", selectedEdgeId ?? "")
        add("routing.enabled", routingEnabled ? 1 : 0)
        let obj: [String: Any] = ["properties": props]
        if let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }
}

// MARK: - LLM Adapter headless (OpenAI-compatible via llm-gateway or mock)
@MainActor
final class LLMAdapterHeadlessInstrument: HeadlessInstrument {
    let displayName: String
    private var provider: String = "openai"
    private var model: String = "gpt-4o-mini"
    private var temperature: Double = 0.2
    private var gatewayURL: String = ProcessInfo.processInfo.environment["LLM_GATEWAY_URL"] ?? ""
    private var streamingEnabled: Bool = false
    private var lastAnswer: String = ""
    private var lastFunctionName: String = ""
    private var tokensTotal: Int = 0
    private var lastTs: String = ""

    init(displayName: String = "LLM Adapter") { self.displayName = displayName }

    func handleVendor(topic: String, data: [String : Any]) -> String? {
        switch topic {
        case "llm.set":
            if let p = data["provider"] as? String { provider = p }
            if let m = data["model"] as? String { model = m }
            if let t = data["temperature"] as? Double { temperature = t }
            if let u = data["gatewayUrl"] as? String { gatewayURL = u }
            if let s = data["streaming"] as? Bool { streamingEnabled = s }
            return snapshot()
        case "llm.chat":
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"llm.chat.started\",\"provider\":\"\(provider)\",\"model\":\"\(model)\"}")
            let useRemote = !gatewayURL.isEmpty || ProcessInfo.processInfo.environment["LLM_GATEWAY_URL"] != nil
            if useRemote, let resp = remoteChat(data: data) {
                applyResponse(resp)
            } else {
                applyResponse(mockChat(data: data))
            }
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"llm.chat.completed\",\"provider\":\"\(provider)\",\"model\":\"\(model)\",\"answer.chars\":\(lastAnswer.utf16.count)}")
            return snapshot()
        default:
            return nil
        }
    }

    func handlePESet(properties: [String : Double]) -> String? {
        for (k,v) in properties {
            switch k {
            case "llm.temperature": temperature = v
            case "streaming.enabled": streamingEnabled = v >= 0.5
            default: break
            }
        }
        return snapshot()
    }

    private func applyResponse(_ r: (answer: String, function: String?, tokens: Int)) {
        lastAnswer = r.answer
        tokensTotal += max(0, r.tokens)
        if let fn = r.function, !fn.isEmpty {
            lastFunctionName = fn
            SimpleMIDISender.recorder.recordSnapshot(vendorJSON: "{\"type\":\"llm.function_call\",\"name\":\"\(fn)\"}")
        } else {
            lastFunctionName = ""
        }
        let f = ISO8601DateFormatter(); lastTs = f.string(from: Date())
    }

    private func mockChat(data: [String: Any]) -> (answer: String, function: String?, tokens: Int) {
        // Simple mock: if user content starts with "CALL:name", emit function_call; else echo with prefix
        var user: String = ""
        if let msgs = data["messages"] as? [[String: Any]] {
            if let last = msgs.last, let role = last["role"] as? String, role == "user", let content = last["content"] as? String { user = content }
        }
        if user.hasPrefix("CALL:") {
            let name = user.dropFirst("CALL:".count).split(separator: "(").first.map(String.init) ?? "tool"
            return (answer: "", function: name, tokens: 8)
        }
        return (answer: "ECHO: \(user)", function: nil, tokens: max(1, user.split(separator: " ").count))
    }

    private func remoteChat(data: [String: Any]) -> (answer: String, function: String?, tokens: Int)? {
        // Minimal synchronous call to llm-gateway /chat; non-streaming only
        let base = gatewayURL.isEmpty ? (ProcessInfo.processInfo.environment["LLM_GATEWAY_URL"] ?? "") : gatewayURL
        guard !base.isEmpty, let url = URL(string: base + "/chat") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = ProcessInfo.processInfo.environment["LLM_GATEWAY_API_KEY"], !key.isEmpty { req.addValue(key, forHTTPHeaderField: "X-API-Key") }
        var body: [String: Any] = [
            "model": model,
            "messages": (data["messages"] as? [[String: Any]]) ?? [["role": "user", "content": "Hello"]]
        ]
        if let f = data["functions"] as? [[String: Any]] { body["functions"] = f }
        if let fc = data["function_call"] { body["function_call"] = fc }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let sem = DispatchSemaphore(value: 0)
        var out: (String, String?, Int)? = nil
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data else { return }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let ans = (obj["answer"] as? String) ?? ""
                let usage = (obj["usage"] as? [String: Any])
                let tokens = (usage?["total_tokens"] as? Int) ?? 0
                let fn = (obj["function_call"] as? [String: Any])?["name"] as? String
                out = (ans, fn, tokens)
            }
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return out
    }

    private func snapshot() -> String? {
        var props: [[String: Any]] = []
        func add(_ name: String, _ value: Any) { props.append(["name": name, "value": value]) }
        add("llm.provider", provider)
        add("llm.model", model)
        add("llm.temperature", temperature)
        add("gateway.url", gatewayURL)
        add("streaming.enabled", streamingEnabled ? 1 : 0)
        add("last.answer", lastAnswer)
        add("last.function.name", lastFunctionName)
        add("tokens.total", tokensTotal)
        add("last.ts", lastTs)
        let obj: [String: Any] = ["properties": props]
        if let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) { return s }
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
        if let name, let inst = HeadlessRegistry.shared.resolve(name) {
            if let vj = Self.decodeVendorJSON(words) {
                if let body = try? JSONSerialization.jsonObject(with: Data(vj.utf8)) as? [String: Any],
                   let topic = body["topic"] as? String, let data = body["data"] as? [String: Any] {
                    if let snap = inst.handleVendor(topic: topic, data: data) { recorder.recordSnapshot(peJSON: snap) }
                }
                return
            }
            if let pj = Self.decodePESetJSON(words) {
                if let snap = inst.handlePESet(properties: pj) { recorder.recordSnapshot(peJSON: snap) }
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
        t.onReceiveUMP = { words in Task { @MainActor in recorder.record(words: words) } }
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
        t.onReceiveUMP = { words in Task { @MainActor in recorder.record(words: words) } }
        alsaTransport = t
        return t
    }

    private static var rtp: RTPMidiSession?
    private static func ensureRTP() -> RTPMidiSession {
        if let t = rtp { return t }
        let t = RTPMidiSession(localName: "midi-service", mtu: 1500, enableDiscovery: false, enableCINegotiation: false)
        try? t.open()
        t.onReceiveUMP = { words in Task { @MainActor in recorder.record(words: words) } }
        rtp = t
        return t
    }

    private static var loopback: LoopbackTransport?
    private static func ensureLoopback() -> LoopbackTransport {
        if let t = loopback { return t }
        let t = LoopbackTransport()
        try? t.open()
        t.onReceiveUMP = { words in Task { @MainActor in recorder.record(words: words) } }
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
    public func registerHeadlessEditor(displayName: String = "Fountain Editor") async {
        await HeadlessRegistry.shared.register(FountainEditorHeadlessInstrument(displayName: displayName))
    }
    public func registerHeadlessCorpus(displayName: String = "Corpus Instrument") async {
        await HeadlessRegistry.shared.register(CorpusHeadlessInstrument(displayName: displayName))
    }
    public func registerHeadlessFlow(displayName: String = "Flow") async {
        await HeadlessRegistry.shared.register(FlowHeadlessInstrument(displayName: displayName))
    }
    public func registerHeadlessLLM(displayName: String = "LLM Adapter") async {
        await HeadlessRegistry.shared.register(LLMAdapterHeadlessInstrument(displayName: displayName))
    }
    public func enableUMPLog(at dirPath: String) async { await MainActor.run { SimpleMIDISender.recorder.enableFileLog(dirPath: dirPath) } }
    public func listHeadless() async -> [String] { await HeadlessRegistry.shared.list() }
    public func registerHeadless(displayName: String, kind: String? = nil) async {
        switch (kind?.lowercased()) {
        case "editor":
            await HeadlessRegistry.shared.register(FountainEditorHeadlessInstrument(displayName: displayName))
        case "corpus":
            await HeadlessRegistry.shared.register(CorpusHeadlessInstrument(displayName: displayName))
        case "canvas", nil:
            fallthrough
        default:
            await HeadlessRegistry.shared.register(CanvasHeadlessInstrument(displayName: displayName))
        }
    }
    public func unregisterHeadless(displayName: String) async { await HeadlessRegistry.shared.unregister(displayName) }
}
