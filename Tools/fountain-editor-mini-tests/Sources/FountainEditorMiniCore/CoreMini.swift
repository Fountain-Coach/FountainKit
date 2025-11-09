import Foundation

public enum FountainEditorMiniCore {
    public struct Beat: Sendable, Equatable { public let index: Int; public let title: String }
    public struct Scene: Sendable, Equatable { public let index: Int; public let title: String; public let anchor: String; public let beats: [Beat] }
    public struct Act: Sendable, Equatable { public let index: Int; public let title: String; public let scenes: [Scene] }
    public struct Structure: Sendable, Equatable { public let etag: String; public let acts: [Act] }

    public static func computeETag(for text: String) -> String {
        var hash: UInt32 = 0
        for b in text.utf8 { hash = (hash &* 16777619) ^ UInt32(b) }
        return String(format: "%08X", hash)
    }

    public struct ParserOptions: Sendable {
        public var acceptSlugVariants: Bool    // INT/EXT, EXT/INT, I/E, EST
        public var acceptNumberedSlugs: Bool   // "1. INT. ..."
        public var gateSlugsWhenSectionsPresent: Bool // if sections exist, only honor "##"
        public var acceptSections: Bool        // honor "## Scene" headings
        public static let extended = ParserOptions(acceptSlugVariants: true, acceptNumberedSlugs: true, gateSlugsWhenSectionsPresent: true, acceptSections: true)
        public static let strict   = ParserOptions(acceptSlugVariants: false, acceptNumberedSlugs: false, gateSlugsWhenSectionsPresent: true, acceptSections: true)
    }

    // Minimal parser: recognizes section headings starting with "#" as acts; scene headings when lines start with screenplay slugs.
    public static func parseStructure(text: String, options: ParserOptions = .extended) -> Structure {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var acts: [Act] = []
        var actIdx = 0
        var sceneIdx = 0
        var scenes: [Scene] = []
        func beginActIfNeeded() { if actIdx == 0 { actIdx = 1 } }
        func pushScene(_ title: String) {
            sceneIdx += 1
            scenes.append(Scene(index: sceneIdx, title: title, anchor: "act\(max(1, actIdx)).scene\(sceneIdx)", beats: []))
        }
        // Build slug regex based on options
        var tokens = ["INT","EXT"]
        if options.acceptSlugVariants { tokens += ["INT/EXT","EXT/INT","I/E","EST"] }
        let tokenAlt = tokens.joined(separator: "|")
        let numbered = options.acceptNumberedSlugs ? "(?:\\d+\\.\\s*)?" : ""
        let pattern = "^" + numbered + "(" + tokenAlt + ")\\b"
        let sceneRegex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let hasExplicitSceneHeadings = lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }
        for raw in lines {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") && !s.hasPrefix("##") {
                if actIdx == 0 { actIdx = 1 } else {
                    acts.append(Act(index: actIdx, title: "ACT \(actIdx)", scenes: scenes))
                    actIdx += 1
                    sceneIdx = 0
                    scenes = []
                }
                continue
            }
            if options.acceptSections, s.hasPrefix("## ") { beginActIfNeeded(); pushScene(String(s.dropFirst(3))) ; continue }
            if !s.isEmpty && !(options.gateSlugsWhenSectionsPresent && hasExplicitSceneHeadings) {
                let range = NSRange(location: 0, length: s.utf16.count)
                if sceneRegex.firstMatch(in: s, options: [], range: range) != nil { beginActIfNeeded(); pushScene(s) }
            }
        }
        let finalIndex = max(1, actIdx)
        acts.append(Act(index: finalIndex, title: "ACT \(finalIndex)", scenes: scenes))
        return Structure(etag: computeETag(for: text), acts: acts)
    }
}

public struct PlacementsMiniCore {
    public struct Placement: Equatable, Sendable { public let id: UUID; public var anchor: String; public var instrumentId: String; public var order: Int?; public var bus: String? }
    public private(set) var byAnchor: [String: [Placement]] = [:]
    public init() {}
    public mutating func add(anchor: String, instrumentId: String, order: Int? = nil, bus: String? = nil) -> Placement {
        let p = Placement(id: UUID(), anchor: anchor, instrumentId: instrumentId, order: order, bus: bus)
        byAnchor[anchor, default: []].append(p)
        return p
    }
    public mutating func update(id: UUID, anchor: String, order: Int? = nil, bus: String? = nil) -> Bool {
        guard var arr = byAnchor[anchor] else { return false }
        if let i = arr.firstIndex(where: { $0.id == id }) {
            var p = arr[i]
            p.order = order ?? p.order
            p.bus = bus ?? p.bus
            arr[i] = p
            byAnchor[anchor] = arr
            return true
        }
        return false
    }
    public mutating func remove(id: UUID, anchor: String) -> Bool {
        guard var arr = byAnchor[anchor] else { return false }
        let before = arr.count
        arr.removeAll { $0.id == id }
        byAnchor[anchor] = arr
        return arr.count != before
    }
    public func list(anchor: String) -> [Placement] { byAnchor[anchor] ?? [] }
}

public enum FountainEditorMiniValidation {
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
        if let chans = channels { for c in chans { if c < 1 || c > 16 { throw MappingError.invalidChannel(c) } } }
        if let g = group { if g < 0 || g > 15 { throw MappingError.invalidGroup(g) } }
        if let f = filters {
            let allowed: Set<String> = ["cv2","m1","pe","util"]
            for x in f { if !allowed.contains(x) { throw MappingError.invalidFilter(x) } }
        }
    }
}
