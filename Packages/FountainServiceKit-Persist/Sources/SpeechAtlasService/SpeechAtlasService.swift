import Foundation
import OpenAPIRuntime
import FountainStoreClient
import TeatroCore

/// Implements the Speech Atlas API on top of the seeded Four Stars corpus.
public struct SpeechAtlasHandlers: APIProtocol, @unchecked Sendable {
    private let store: FountainStoreClient
    private let corpusId: String
    private let pageFetchBatchSize = 200
    private let segmentFetchBatchSize = 256
    private let summaryContextWindow = 3

    public init(store: FountainStoreClient, corpusId: String = "the-four-stars") {
        self.store = store
        self.corpusId = corpusId
    }

    // MARK: - APIProtocol

    public func speechesList(_ input: Operations.speechesList.Input) async throws -> Operations.speechesList.Output {
        guard case let .json(request) = input.body else {
            return .badRequest(.init(body: .json(.init(error: "Unsupported content type"))))
        }

        guard request.limit > 0, request.limit <= 500, request.offset >= 0 else {
            return .badRequest(.init(body: .json(.init(error: "limit must be between 1 and 500; offset must be >= 0"))))
        }

        let limit = Int(request.limit)
        let offset = Int(request.offset)
        let speakerSlug = request.speaker.map(slugify)
        let pages = try await loadPages()
        let filteredPages = filterPages(pages: pages, act: request.act, scene: request.scene)

        let fetchStrategy = SpeechFetchStrategy(
            pages: pages,
            filteredPages: filteredPages,
            speakerSlug: speakerSlug
        )

        let segmentsResult = try await fetchSegments(
            strategy: fetchStrategy,
            limit: limit,
            offset: offset
        )

        let listItems = segmentsResult.segments.compactMap { segment -> Components.Schemas.SpeechListItem? in
            guard let pageInfo = pages[segment.pageId],
                  let metadata = augment(segment: segment, page: pageInfo) else { return nil }
            return metadata.item
        }

        let payload = Components.Schemas.SpeechList(
            total: Int32(segmentsResult.total),
            items: listItems
        )

        return .ok(.init(body: .json(.init(result: payload))))
    }

    public func speechesDetail(_ input: Operations.speechesDetail.Input) async throws -> Operations.speechesDetail.Output {
        guard case let .json(request) = input.body else {
            return .badRequest(.init(body: .json(.init(error: "Unsupported content type"))))
        }

        guard let identifier = SpeechIdentifier(rawValue: request.speech_id) else {
            return .badRequest(.init(body: .json(.init(error: "Invalid speech identifier"))))
        }

        guard let segment = try await fetchSegment(id: identifier.segmentId) else {
            return .badRequest(.init(body: .json(.init(error: "Speech not found"))))
        }

        let pages = try await loadPages()
        guard let pageInfo = pages[segment.pageId],
              let enriched = augment(segment: segment, page: pageInfo) else {
            return .badRequest(.init(body: .json(.init(error: "Unable to resolve speech metadata"))))
        }

        let includeContext = request.include_context ?? true
        let context: (before: [Components.Schemas.SpeechListItem]?, after: [Components.Schemas.SpeechListItem]?)
        if includeContext {
            context = try await fetchContext(
                around: segment,
                pageInfo: pageInfo
            )
        } else {
            context = (nil, nil)
        }

        let detail = Components.Schemas.SpeechDetail(
            speech: enriched.item,
            lines: enriched.lines,
            context_before: context.before,
            context_after: context.after
        )

        return .ok(.init(body: .json(.init(result: detail))))
    }

    public func speechesSummary(_ input: Operations.speechesSummary.Input) async throws -> Operations.speechesSummary.Output {
        guard case let .json(request) = input.body else {
            return .badRequest(.init(body: .json(.init(error: "Unsupported content type"))))
        }

        guard !request.speech_ids.isEmpty else {
            return .badRequest(.init(body: .json(.init(error: "speech_ids must not be empty"))))
        }

        guard request.max_speakers ?? 5 >= 1, request.max_speakers ?? 5 <= 20 else {
            return .badRequest(.init(body: .json(.init(error: "max_speakers must be between 1 and 20"))))
        }

        let uniqueIds = Array(Set(request.speech_ids))
        let pages = try await loadPages()

        var records: [SpeechRecord] = []
        for rawId in uniqueIds {
            guard let identifier = SpeechIdentifier(rawValue: rawId),
                  let segment = try await fetchSegment(id: identifier.segmentId),
                  let page = pages[segment.pageId],
                  let enriched = augment(segment: segment, page: page) else {
                return .badRequest(.init(body: .json(.init(error: "Speech \(rawId) not found"))))
            }
            records.append(enriched)
        }

        let summary = buildSummary(
            records: records,
            maxSpeakers: Int(request.max_speakers ?? 5)
        )

        return .ok(.init(body: .json(.init(result: summary))))
    }

    public func speechesScript(_ input: Operations.speechesScript.Input) async throws -> Operations.speechesScript.Output {
        guard case let .json(req) = input.body else {
            return .badRequest(.init(body: .json(.init(error: "Unsupported content type"))))
        }
        let act = req.act
        let scene = req.scene
        let layout = (req.layout?.rawValue ?? "readable").lowercased()
        let format = (req.format?.rawValue ?? "markdown").lowercased()

        guard let sourceURL = resolveFountainSource() else {
            return .badRequest(.init(body: .json(.init(error: "Fountain source not found"))))
        }
        let text = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        guard !text.isEmpty else {
            return .badRequest(.init(body: .json(.init(error: "Empty source"))))
        }

        // Normalise and parse via Teatro
        let normalised = normaliseFountain(text: text)
        let nodes = FountainParser().parse(normalised)
        guard let slice = sliceScene(nodes: nodes, act: act, scene: scene) else {
            return .badRequest(.init(body: .json(.init(error: "Scene not found"))))
        }
        let header = sceneHeader(from: slice.header, act: act, scene: scene)

        // Build blocks with .fountain semantics
        let blocks = buildBlocks(from: slice.nodes)

        if format == "json" {
            let items = blocks.map { Components.Schemas.ScriptBlock(speaker: $0.speaker, lines: $0.lines) }
            let payload = Components.Schemas.SceneScriptResponse(result: .init(header: header, markdown: nil, blocks: items))
            return .ok(.init(body: .json(payload)))
        }
        // Markdown rendering with layout override
        var md: [String] = ["# \(header)"]
        switch layout {
        case "screenplay":
            // simple screenplay-like: center scene heading (Markdown can't center reliably), uppercase speakers
            for block in blocks {
                md.append("\n**\(block.speaker.uppercased())**")
                for line in block.lines { md.append("    \(line)") }
            }
        default: // readable
            for block in blocks {
                md.append("\n**\(block.speaker)**")
                for line in block.lines { md.append(line) }
            }
        }
        let content = md.joined(separator: "\n")
        let payload = Components.Schemas.SceneScriptResponse(result: .init(header: header, markdown: content, blocks: nil))
        return .ok(.init(body: .json(payload)))
    }

    // MARK: - Fountain helpers
    private func resolveFountainSource() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let path = env["FOUNTAIN_SOURCE_PATH"], !path.isEmpty { return URL(fileURLWithPath: path) }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let defaultPath = cwd.appendingPathComponent("Workspace/the-four-stars/the four stars")
        return FileManager.default.fileExists(atPath: defaultPath.path) ? defaultPath : nil
    }

    private func normaliseFountain(text: String) -> String {
        var out: [String] = []
        let lines = text.components(separatedBy: "\n")
        for (idx, raw) in lines.enumerated() {
            if idx == 0 { continue } // skip title line
            if let act = normaliseActLine(raw) { out.append(act); out.append(""); continue }
            if let scene = normaliseSceneLine(raw) { out.append(scene); out.append(""); continue }
            out.append(raw)
        }
        return out.joined(separator: "\n")
    }

    private func normaliseActLine(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("****"), t.uppercased().contains("ACT"), t.hasSuffix("****") else { return nil }
        let inner = t.trimmingCharacters(in: CharacterSet(charactersIn: "* ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.uppercased().hasPrefix("ACT") else { return nil }
        return "# \(inner)"
    }
    private func normaliseSceneLine(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("****"), t.uppercased().contains("SCENE"), t.hasSuffix("****") else { return nil }
        let inner = t.trimmingCharacters(in: CharacterSet(charactersIn: "* ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.uppercased().hasPrefix("SCENE") else { return nil }
        return "## \(inner)"
    }

    private func sliceScene(nodes: [FountainNode], act: String, scene: String) -> (header: String, nodes: [FountainNode])? {
        var currentAct = ""
        var startIndex: Int?
        var headerText = ""
        for (i, n) in nodes.enumerated() {
            switch n.type {
            case .section(let level):
                if level == 1 { currentAct = stripSections(from: n.rawText).replacingOccurrences(of: "ACT ", with: "").trimmingCharacters(in: .whitespaces) }
            case .sceneHeading:
                if currentAct == act {
                    let desc = stripSections(from: n.rawText)
                    // Expect pattern: SCENE <roman>. <location>
                    let u = desc.uppercased()
                    if u.hasPrefix("SCENE \(scene.uppercased())") {
                        startIndex = i + 1
                        headerText = desc
                    } else if startIndex != nil {
                        // next scene reached
                        let slice = Array(nodes[(startIndex!)..<i])
                        return (header: headerText, nodes: slice)
                    }
                }
            default:
                break
            }
        }
        if let s = startIndex { return (header: headerText, nodes: Array(nodes[s...])) }
        return nil
    }

    private func stripSections(from raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sceneHeader(from heading: String, act: String, scene: String) -> String {
        // Heading like: SCENE II. Lawn before the Duke's palace.
        let parts = heading.split(separator: ".", maxSplits: 1).map(String.init)
        let location = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
        if let loc = location, !loc.isEmpty { return "Act \(act) Scene \(scene) – \(loc)" }
        return "Act \(act) Scene \(scene)"
    }

    private func buildBlocks(from nodes: [FountainNode]) -> [(speaker: String, lines: [String])] {
        var blocks: [(String, [String])] = []
        var currentSpeaker: String? = nil
        var buf: [String] = []
        func flush() { if let s = currentSpeaker, !buf.isEmpty { blocks.append((s, buf)); buf.removeAll() } }
        for n in nodes {
            switch n.type {
            case .character:
                flush()
                currentSpeaker = n.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            case .parenthetical:
                if currentSpeaker != nil {
                    buf.append("(")
                    buf.append(n.rawText)
                }
            case .dialogue:
                if currentSpeaker != nil { buf.append(n.rawText) }
            case .action:
                flush()
                currentSpeaker = "[STAGE]"
                buf = [n.rawText]
                flush()
                currentSpeaker = nil
            default:
                continue
            }
        }
        flush()
        // Normalize speaker names to display-friendly (uppercase words separated by spaces), allow alias overrides
        let map = speakerAliasMap()
        let out = blocks.map { spk, lines in
            let key = spk.lowercased()
            if let alias = map[key] { return (alias, lines) }
            return (speakerDisplayName(from: key), lines)
        }
        return out
    }

    // MARK: - Speaker alias mapping
    private func speakerAliasMap() -> [String: String] {
        var out: [String: String] = [:]
        let env = ProcessInfo.processInfo.environment
        if let mapStr = env["SPEAKER_MAP"], !mapStr.isEmpty {
            // Format: slug=Display,slug2=Display Two
            for pair in mapStr.split(separator: ",") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { out[parts[0].lowercased()] = parts[1] }
            }
        }
        // File fallback: Configuration/speakers.map lines: slug=Display
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let defaultPath = cwd.appendingPathComponent("Configuration/speakers.map")
        if FileManager.default.fileExists(atPath: defaultPath.path),
           let data = try? Data(contentsOf: defaultPath), let text = String(data: data, encoding: .utf8) {
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { out[parts[0].lowercased()] = parts[1] }
            }
        }
        return out
    }

    // MARK: - Segment Fetching

    private struct SpeechFetchStrategy: Sendable {
        let pages: [String: PageMetadata]
        let filteredPages: [String: PageMetadata]
        let speakerSlug: String?

        var hasPageFilter: Bool { filteredPages.count != pages.count }
    }

    private func fetchSegments(
        strategy: SpeechFetchStrategy,
        limit: Int,
        offset: Int
    ) async throws -> (total: Int, segments: [Segment]) {
        if !strategy.hasPageFilter && strategy.speakerSlug == nil {
            return try await querySegmentsDirect(limit: limit, offset: offset)
        }

        if !strategy.hasPageFilter, let speakerSlug = strategy.speakerSlug {
            return try await querySegmentsBySpeaker(speakerSlug: speakerSlug, limit: limit, offset: offset)
        }

        // Page-constrained (optionally with speaker filter): gather segments per page and page results locally.
        var totalMatches = 0
        var collected: [Segment] = []
        var remainingOffset = offset

        for page in strategy.filteredPages.values.sorted(by: { $0.sortKey < $1.sortKey }) {
            let segments = try await loadSegments(for: page.page.pageId)
            let filtered = segments.filter { segment in
                guard let info = parseSegmentIdentifier(segment.segmentId) else { return false }
                if let speakerSlug = strategy.speakerSlug, info.speakerSlug != speakerSlug {
                    return false
                }
                return true
            }

            totalMatches += filtered.count

            for segment in filtered {
                if remainingOffset > 0 {
                    remainingOffset -= 1
                    continue
                }
                collected.append(segment)
                if collected.count == limit {
                    return (totalMatches, collected)
                }
            }
        }

        return (totalMatches, collected)
    }

    private func querySegmentsDirect(limit: Int, offset: Int) async throws -> (total: Int, segments: [Segment]) {
        let query = Query(
            filters: ["kind": "speech"],
            sort: [("segmentId", true)],
            limit: limit,
            offset: offset
        )
        let response = try await store.query(corpusId: corpusId, collection: "segments", query: query)
        let segments = try response.documents.map { try JSONDecoder().decode(Segment.self, from: $0) }
        return (response.total, segments)
    }

    private func querySegmentsBySpeaker(speakerSlug: String, limit: Int, offset: Int) async throws -> (total: Int, segments: [Segment]) {
        let prefix = "\(speakerSlug)-"
        let query = Query(
            mode: .prefixScan("segmentId", prefix),
            sort: [("segmentId", true)],
            limit: limit,
            offset: offset
        )
        let response = try await store.query(corpusId: corpusId, collection: "segments", query: query)
        let segments = try response.documents.map { try JSONDecoder().decode(Segment.self, from: $0) }
        return (response.total, segments)
    }

    private func fetchSegment(id: String) async throws -> Segment? {
        let response = try await store.query(
            corpusId: corpusId,
            collection: "segments",
            query: Query(mode: .byId(id))
        )
        guard let payload = response.documents.first else { return nil }
        return try JSONDecoder().decode(Segment.self, from: payload)
    }

    private func loadSegments(for pageId: String) async throws -> [Segment] {
        var collected: [Segment] = []
        var offset = 0
        while true {
            let query = Query(
                filters: ["pageId": pageId, "kind": "speech"],
                sort: [("segmentId", true)],
                limit: segmentFetchBatchSize,
                offset: offset
            )
            let response = try await store.query(corpusId: corpusId, collection: "segments", query: query)
            let batch = try response.documents.map { try JSONDecoder().decode(Segment.self, from: $0) }
            collected.append(contentsOf: batch)
            if collected.count >= response.total || batch.isEmpty { break }
            offset += segmentFetchBatchSize
        }
        return collected
    }

    // MARK: - Page Metadata

    private actor PageCache {
        private var pages: [String: [String: PageMetadata]] = [:]

        func cachedPages(for corpusId: String) -> [String: PageMetadata]? {
            pages[corpusId]
        }

        func store(_ pages: [String: PageMetadata], for corpusId: String) {
            self.pages[corpusId] = pages
        }
    }

    private let cache = PageCache()

    private func loadPages() async throws -> [String: PageMetadata] {
        if let memoized = await cache.cachedPages(for: corpusId), !memoized.isEmpty {
            return memoized
        }

        var allPages: [Page] = []
        var offset = 0

        while true {
            let response = try await store.listPages(corpusId: corpusId, limit: pageFetchBatchSize, offset: offset)
            allPages.append(contentsOf: response.pages)
            if allPages.count >= response.total { break }
            offset += pageFetchBatchSize
        }

        let mapped: [String: PageMetadata] = Dictionary(uniqueKeysWithValues: allPages.compactMap { page in
            guard let metadata = PageMetadata(page: page) else { return nil }
            return (page.pageId, metadata)
        })

        await cache.store(mapped, for: corpusId)
        return mapped
    }

    private func filterPages(pages: [String: PageMetadata], act: Components.Schemas.ActCode?, scene: Components.Schemas.SceneCode?) -> [String: PageMetadata] {
        pages.filter { _, metadata in
            if let act, metadata.actCode.caseInsensitiveCompare(act) != .orderedSame {
                return false
            }
            if let scene, metadata.sceneCode.caseInsensitiveCompare(scene) != .orderedSame {
                return false
            }
            return true
        }
    }

    // MARK: - Augmentation

    private struct SpeechRecord {
        let item: Components.Schemas.SpeechListItem
        let lines: [String]
        let actCode: String
        let sceneCode: String
        let speakerSlug: String
    }

    private func augment(segment: Segment, page: PageMetadata) -> SpeechRecord? {
        guard let identifier = parseSegmentIdentifier(segment.segmentId) else { return nil }

        let speechId = SpeechIdentifier(pageId: page.page.pageId, segmentId: segment.segmentId).rawValue
        let snippet = segment.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
        let lines = segment.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let item = Components.Schemas.SpeechListItem(
            speech_id: speechId,
            act: page.actCode,
            scene: page.sceneCode,
            speaker: speakerDisplayName(from: identifier.speakerSlug),
            location: page.location,
            index: Int32(identifier.index),
            snippet: String(snippet)
        )

        return SpeechRecord(item: item, lines: lines, actCode: page.actCode, sceneCode: page.sceneCode, speakerSlug: identifier.speakerSlug)
    }

    private func fetchContext(around segment: Segment, pageInfo: PageMetadata) async throws -> (before: [Components.Schemas.SpeechListItem]?, after: [Components.Schemas.SpeechListItem]?) {
        let segments = try await loadSegments(for: pageInfo.page.pageId)
        guard let enriched = augment(segment: segment, page: pageInfo) else {
            return (nil, nil)
        }

        let indexed = segments.compactMap { seg -> SpeechRecord? in
            guard let record = augment(segment: seg, page: pageInfo) else { return nil }
            return record
        }

        guard let position = indexed.firstIndex(where: { $0.item.speech_id == enriched.item.speech_id }) else {
            return (nil, nil)
        }

        let startBefore = max(0, position - summaryContextWindow)
        let beforeSlice = indexed[startBefore..<position]
        let afterSlice = indexed[(position + 1)..<min(indexed.count, position + 1 + summaryContextWindow)]

        return (
            beforeSlice.isEmpty ? nil : beforeSlice.map(\.item),
            afterSlice.isEmpty ? nil : afterSlice.map(\.item)
        )
    }

    // MARK: - Summary

    private func buildSummary(records: [SpeechRecord], maxSpeakers: Int) -> Components.Schemas.SpeechSummary {
        let speakerCounts = Dictionary(grouping: records, by: { $0.item.speaker })
            .mapValues { Int32($0.count) }

        let topSpeakers = speakerCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(maxSpeakers)
            .map { Components.Schemas.SpeakerCount(speaker: $0.key, speeches: $0.value) }

        let actCounts = Dictionary(grouping: records, by: { $0.actCode })
            .map { Components.Schemas.ActSummary(act: $0.key, speech_count: Int32($0.value.count)) }
            .sorted { $0.act < $1.act }

        let sceneCounts = Dictionary(grouping: records, by: { SceneKey(act: $0.actCode, scene: $0.sceneCode) })
            .map { Components.Schemas.SceneSummary(act: $0.key.act, scene: $0.key.scene, speech_count: Int32($0.value.count)) }
            .sorted {
                if $0.act == $1.act {
                    return $0.scene < $1.scene
                }
                return $0.act < $1.act
            }

        return Components.Schemas.SpeechSummary(
            speech_count: Int32(records.count),
            top_speakers: topSpeakers,
            acts_covered: actCounts.isEmpty ? nil : actCounts,
            scenes_covered: sceneCounts.isEmpty ? nil : sceneCounts
        )
    }

    // MARK: - Identifiers & Helpers

    private struct SpeechIdentifier: Hashable {
        let pageId: String
        let segmentId: String

        init(pageId: String, segmentId: String) {
            self.pageId = pageId
            self.segmentId = segmentId
        }

        init?(rawValue: String) {
            let components = rawValue.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count == 2 else { return nil }
            self.pageId = String(components[0])
            self.segmentId = String(components[1])
        }

        var rawValue: String { "\(pageId)/\(segmentId)" }
    }

    private struct SegmentIdentifier {
        let speakerSlug: String
        let index: Int
    }

    private struct SceneKey: Hashable {
        let act: String
        let scene: String
    }

    private func parseSegmentIdentifier(_ raw: String) -> SegmentIdentifier? {
        guard let dash = raw.lastIndex(of: "-") else { return nil }
        let speakerPart = raw[..<dash]
        let indexPart = raw[raw.index(after: dash)...]
        guard let index = Int(indexPart) else { return nil }
        return SegmentIdentifier(speakerSlug: String(speakerPart), index: index)
    }

    private func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var cleaned = lowered.replacingOccurrences(of: " ", with: "-")
        cleaned = cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.map(String.init).joined()
        cleaned = cleaned.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func speakerDisplayName(from slug: String) -> String {
        slug.split(separator: "-").map { part in
            part.uppercased()
        }.joined(separator: " ")
    }

    // MARK: - Page Metadata

    private struct PageMetadata: Sendable {
        let page: Page
        let actCode: String
        let sceneCode: String
        let location: String?

        init?(page: Page) {
            self.page = page
            guard let parsed = PageMetadata.parse(title: page.title) else { return nil }
            self.actCode = parsed.act
            self.sceneCode = parsed.scene
            self.location = parsed.location
        }

        var sortKey: String {
            "\(actCode)-\(sceneCode)-\(page.pageId)"
        }

        private static func parse(title: String) -> (act: String, scene: String, location: String?)? {
            let components = title.components(separatedBy: "–")
            let header = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let location = components.count > 1 ? components[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

            let pattern = #"Act\s+([IVXLC]+)\s+Scene\s+([IVXLC]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: header, range: NSRange(location: 0, length: header.utf16.count)),
                  match.numberOfRanges >= 3,
                  let actRange = Range(match.range(at: 1), in: header),
                  let sceneRange = Range(match.range(at: 2), in: header) else {
                return nil
            }

            let act = String(header[actRange]).uppercased()
            let scene = String(header[sceneRange]).uppercased()
            return (act, scene, location)
        }
    }
}
