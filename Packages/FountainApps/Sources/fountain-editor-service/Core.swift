import Foundation

// MARK: - Core helpers for the Fountain Editor service

public struct FountainEditorCore {
    public struct Scene { public let index: Int; public let title: String; public let anchor: String; public let beats: [Beat] }
    public struct Beat { public let index: Int; public let title: String }
    public struct Act { public let index: Int; public let title: String; public let scenes: [Scene] }
    public struct Structure { public let etag: String; public let acts: [Act] }

    public static func computeETag(for text: String) -> String {
        // Same simple FNV-1a 32-bit used in the UI model for determinism
        var hash: UInt32 = 0
        for b in text.utf8 { hash = (hash &* 16777619) ^ UInt32(b) }
        return String(format: "%08X", hash)
    }

    public static func parseStructure(text: String) -> Structure {
        // Minimal parser inspired by the test helper in Tools/fountain-editor-mini-tests.
        // Recognizes:
        // - Act headings as lines starting with a single '#'
        // - Scene headings as lines starting with '## '
        // - Fallback scene detection on screenplay slugs (INT/EXT variants)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var acts: [Act] = []
        var actIdx = 0
        var sceneIdx = 0
        var scenes: [Scene] = []
        func ensureAct() { if actIdx == 0 { actIdx = 1 } }
        func pushScene(_ title: String) {
            sceneIdx += 1
            scenes.append(Scene(index: sceneIdx, title: title, anchor: "act\(max(1, actIdx)).scene\(sceneIdx)", beats: []))
        }
        // Build slug regex for scene headings (INT., EXT., etc.)
        let tokens = ["INT","EXT","INT/EXT","EXT/INT","I/E","EST"]
        let tokenAlt = tokens.joined(separator: "|")
        let pattern = "^(?:\\d+\\.\\s*)?(" + tokenAlt + ")\\b"
        let sceneRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let hasExplicitSceneHeadings = lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }
        for raw in lines {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") && !s.hasPrefix("##") {
                // Start new act boundary
                if actIdx == 0 {
                    actIdx = 1
                } else {
                    acts.append(Act(index: actIdx, title: "ACT \(actIdx)", scenes: scenes))
                    actIdx += 1
                    sceneIdx = 0
                    scenes = []
                }
                continue
            }
            if s.hasPrefix("## ") {
                ensureAct(); pushScene(String(s.dropFirst(3)))
                continue
            }
            if !s.isEmpty && !hasExplicitSceneHeadings {
                if let re = sceneRegex {
                    let range = NSRange(location: 0, length: s.utf16.count)
                    if re.firstMatch(in: s, options: [], range: range) != nil { ensureAct(); pushScene(s) }
                }
            }
        }
        let finalIndex = max(1, actIdx)
        acts.append(Act(index: finalIndex, title: "ACT \(finalIndex)", scenes: scenes))
        return Structure(etag: computeETag(for: text), acts: acts)
    }
}

// MARK: - In-memory placements for TDD
public struct PlacementsCore {
    public struct Placement: Equatable, Sendable {
        public let id: UUID; public var anchor: String; public var instrumentId: String; public var order: Int?; public var bus: String?
        public init(id: UUID, anchor: String, instrumentId: String, order: Int? = nil, bus: String? = nil) {
            self.id = id; self.anchor = anchor; self.instrumentId = instrumentId; self.order = order; self.bus = bus
        }
    }
    public private(set) var listByAnchor: [String: [Placement]] = [:]

    public init() {}

    public mutating func add(anchor: String, instrumentId: String, order: Int? = nil, bus: String? = nil) -> Placement {
        let p = Placement(id: UUID(), anchor: anchor, instrumentId: instrumentId, order: order, bus: bus)
        listByAnchor[anchor, default: []].append(p)
        return p
    }
    public mutating func update(id: UUID, anchor: String, order: Int? = nil, bus: String? = nil) -> Bool {
        guard var arr = listByAnchor[anchor] else { return false }
        if let idx = arr.firstIndex(where: { $0.id == id }) {
            var p = arr[idx]
            p.order = order ?? p.order
            p.bus = bus ?? p.bus
            arr[idx] = p
            listByAnchor[anchor] = arr
            return true
        }
        return false
    }
    public mutating func remove(id: UUID, anchor: String) -> Bool {
        guard var arr = listByAnchor[anchor] else { return false }
        let before = arr.count
        arr.removeAll { $0.id == id }
        listByAnchor[anchor] = arr
        return arr.count != before
    }
    public func list(anchor: String) -> [Placement] { listByAnchor[anchor] ?? [] }
}

// MARK: - ETag + Mapping validation
public enum FountainEditorValidation {
    public enum MappingError: Error { case invalidChannel(Int), invalidGroup(Int), invalidFilter(String) }

    public static func normalizeETagHeader(_ header: String?) -> String? {
        guard var s = header?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("W/") { s.removeFirst(2) }
        if s.first == "\"" && s.last == "\"" && s.count >= 2 { s = String(s.dropFirst().dropLast()) }
        return s
    }
    public static func ifMatchSatisfied(currentETag: String, header: String?) -> Bool {
        guard let h = normalizeETagHeader(header) else { return false }
        return h == currentETag || h == "*"
    }

    public static func validateMapping(channels: [Int]?, group: Int?, filters: [String]?) throws {
        if let chans = channels {
            for c in chans { if c < 1 || c > 16 { throw MappingError.invalidChannel(c) } }
        }
        if let g = group { if g < 0 || g > 15 { throw MappingError.invalidGroup(g) } }
        if let f = filters {
            let allowed: Set<String> = ["cv2","m1","pe","util"]
            for x in f { if !allowed.contains(x) { throw MappingError.invalidFilter(x) } }
        }
    }
}

// MARK: - In-memory script store (core-level semantics for TDD)
actor InMemoryScriptStore {
    private var scripts: [String: String] = [:] // corpusId -> text

    func get(corpusId: String) -> (etag: String, text: String)? {
        guard let text = scripts[corpusId] else { return nil }
        return (FountainEditorCore.computeETag(for: text), text)
    }

    // Returns true on save (HTTP 204), false on ETag mismatch/absent (HTTP 409)
    func put(corpusId: String, text: String, ifMatch: String?) -> Bool {
        let current = scripts[corpusId]
        let currentETag = current.map { FountainEditorCore.computeETag(for: $0) }
        guard FountainEditorValidation.ifMatchSatisfied(currentETag: currentETag ?? "", header: ifMatch) else {
            // Require If-Match, allow "*" for create
            return false
        }
        scripts[corpusId] = text
        return true
    }
}
