import Foundation
import SwiftCursesKit
import EngraverChatCore
import FountainAIAdapters
import FountainAIKit
import FountainStoreClient

// MARK: - CLI Options

struct ChatCLIOptions {
    var transcriptLines: Int = 18
    var diagnosticsLines: Int = 8
    var corpusLines: Int = 8
    var diagnosticsInitiallyVisible: Bool = false
    var overrides: [String: String] = [:]
    var disablePersistence: Bool = false
    var previewOnly: Bool = false

    static func parse(_ arguments: [String]) -> ChatCLICommand {
        var options = ChatCLIOptions()
        var iterator = arguments.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "-h", "--help":
                return .help
            case "--transcript-lines":
                if let value = iterator.next(), let parsed = Int(value) {
                    options.transcriptLines = max(4, parsed)
                }
            case "--diagnostics-lines":
                if let value = iterator.next(), let parsed = Int(value) {
                    options.diagnosticsLines = max(2, parsed)
                }
            case "--corpus-lines":
                if let value = iterator.next(), let parsed = Int(value) {
                    options.corpusLines = max(2, parsed)
                }
            case "--corpus":
                if let value = iterator.next() {
                    options.overrides["ENGRAVER_CORPUS_ID"] = value
                }
            case "--collection":
                if let value = iterator.next() {
                    options.overrides["ENGRAVER_COLLECTION"] = value
                }
            case "--model":
                if let value = iterator.next() {
                    options.overrides["ENGRAVER_DEFAULT_MODEL"] = value
                    options.overrides["ENGRAVER_MODELS"] = value
                }
            case "--system-prompt":
                if let value = iterator.next() {
                    options.overrides["ENGRAVER_SYSTEM_PROMPT"] = value
                }
            case "--gateway-url":
                if let value = iterator.next() {
                    options.overrides["FOUNTAIN_GATEWAY_URL"] = value
                }
            case "--bearer":
                if let value = iterator.next() {
                    options.overrides["GATEWAY_BEARER"] = value
                }
            case "--debug":
                options.overrides["ENGRAVER_DEBUG"] = "1"
                options.diagnosticsInitiallyVisible = true
            case "--no-debug":
                options.overrides["ENGRAVER_DEBUG"] = "0"
                options.diagnosticsInitiallyVisible = false
            case "--disable-persistence":
                options.disablePersistence = true
                options.overrides["ENGRAVER_DISABLE_PERSISTENCE"] = "true"
            case "--preview":
                options.previewOnly = true
            default:
                continue
            }
        }
        return .run(options)
    }
}

enum ChatCLICommand {
    case help
    case run(ChatCLIOptions)

    static var helpText: String {
        """
        Engraver Chat TUI

        Usage: swift run engraver-chat-tui [options]

          --transcript-lines <count>   Visible rows in the conversation log (default: 18)
          --diagnostics-lines <count>  Visible rows in the diagnostics log (default: 8)
          --corpus-lines <count>       Visible rows in the corpus browser (default: 8)
          --corpus <id>                Override ENGRAVER_CORPUS_ID (default: engraver-space)
          --collection <name>          Override ENGRAVER_COLLECTION (default: chat-turns)
          --model <name>               Set ENGRAVER_DEFAULT_MODEL and MODELS to a single value
          --system-prompt <text>       Override ENGRAVER_SYSTEM_PROMPT
          --gateway-url <url>          Override FOUNTAIN_GATEWAY_URL
          --bearer <token>             Override GATEWAY_BEARER
          --debug                      Enable diagnostics (ENGRAVER_DEBUG=1)
          --no-debug                   Disable diagnostics (ENGRAVER_DEBUG=0)
          --disable-persistence        Skip FountainStore persistence for this session
          --preview                    Print a static transcript preview then exit
          -h, --help                   Show this help message
        """
    }
}

// MARK: - Snapshot Structures

struct ChatSnapshot: Sendable {
    var turns: [EngraverChatTurn]
    var activeTokens: [String]
    var diagnostics: [String]
    var state: EngraverChatState
    var lastError: String?
    var selectedModel: String
    var availableModels: [String]
    var corpusId: String
    var collection: String
    var sessionId: UUID
    var sessionName: String?
    var sessionStartedAt: Date
}

struct CorpusSessionSummary: Sendable {
    var sessionId: UUID
    var name: String
    var startedAt: Date
    var updatedAt: Date
    var turnCount: Int
    var lastPrompt: String
    var lastAnswer: String
    var model: String?
}

// MARK: - Session Actor

actor ChatSession {
    private let configuration: EngraverStudioConfiguration
    private let viewModel: EngraverChatViewModel

    init(configuration: EngraverStudioConfiguration) async {
        self.configuration = configuration
        // Choose provider based on configuration, mirroring EngraverStudioRoot
        let client: ChatStreaming = {
            if configuration.bypassGateway {
                if configuration.provider == "openai" {
                    return DirectOpenAIChatClient(apiKey: configuration.openAIAPIKey)
                } else { // local default (e.g., Ollama-compatible endpoint)
                    return DirectOpenAIChatClient(apiKey: nil, endpoint: configuration.localEndpoint)
                }
            } else {
                return GatewayChatClient(
                    baseURL: configuration.gatewayURL,
                    tokenProvider: configuration.tokenProvider()
                )
            }
        }()
        self.viewModel = await MainActor.run {
            EngraverChatViewModel(
                chatClient: client,
                persistenceStore: configuration.persistenceStore,
                corpusId: configuration.corpusId,
                collection: configuration.collection,
                availableModels: configuration.availableModels,
                defaultModel: configuration.defaultModel,
                debugEnabled: configuration.debugEnabled,
                awarenessBaseURL: configuration.awarenessBaseURL,
                bootstrapBaseURL: configuration.bootstrapBaseURL,
                bearerToken: configuration.bearerToken,
                seedingConfiguration: Self.mapSeeding(configuration.seedingConfiguration),
                fountainRepoRoot: configuration.fountainRepoRoot
            )
        }
    }

    private static func mapSeeding(_ cfg: EngraverStudioConfiguration.SeedingConfiguration?) -> SeedingConfiguration? {
        guard let cfg else { return nil }
        let sources = cfg.sources.map { s in
            SeedingConfiguration.Source(name: s.name, url: s.url, corpusId: s.corpusId, labels: s.labels)
        }
        let browser = SeedingConfiguration.Browser(
            baseURL: cfg.browser.baseURL,
            apiKey: cfg.browser.apiKey,
            mode: SeedingConfiguration.Browser.Mode(rawValue: cfg.browser.mode.rawValue) ?? .standard,
            defaultLabels: cfg.browser.defaultLabels,
            pagesCollection: cfg.browser.pagesCollection,
            segmentsCollection: cfg.browser.segmentsCollection,
            entitiesCollection: cfg.browser.entitiesCollection,
            tablesCollection: cfg.browser.tablesCollection,
            storeOverride: cfg.browser.storeOverride.map { .init(url: $0.url, apiKey: $0.apiKey, timeoutMs: $0.timeoutMs) }
        )
        return SeedingConfiguration(sources: sources, browser: browser)
    }

    func submit(prompt: String) async {
        await MainActor.run {
            let prompts = viewModel.makeSystemPrompts(base: configuration.systemPrompts)
            viewModel.send(prompt: prompt, systemPrompts: prompts)
        }
    }

    func cancel() async {
        await MainActor.run {
            viewModel.cancelStreaming()
        }
    }

    func snapshot() async -> ChatSnapshot {
        let corpus = configuration.corpusId
        let collection = configuration.collection
        return await MainActor.run {
            ChatSnapshot(
                turns: viewModel.turns,
                activeTokens: viewModel.activeTokens,
                diagnostics: viewModel.diagnostics,
                state: viewModel.state,
                lastError: viewModel.lastError,
                selectedModel: viewModel.selectedModel,
                availableModels: viewModel.availableModels,
                corpusId: corpus,
                collection: collection,
                sessionId: viewModel.sessionId,
                sessionName: viewModel.sessionName,
                sessionStartedAt: viewModel.sessionStartedAt
            )
        }
    }

    func persistenceEnabled() -> Bool {
        configuration.persistenceStore != nil
    }

    func startNewSession(named name: String? = nil) async {
        await MainActor.run {
            viewModel.startNewSession(named: name)
        }
    }

    func fetchCorpusSessions(limit: Int) async throws -> [CorpusSessionSummary] {
        guard let store = configuration.persistenceStore else { return [] }
        let fetchLimit = min(500, max(60, limit * 6))
        let query = Query(sort: [("createdAt", false)], limit: fetchLimit)
        let response = try await store.query(
            corpusId: configuration.corpusId,
            collection: configuration.collection,
            query: query
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var sessions: [UUID: SessionAccumulator] = [:]
        for data in response.documents {
            guard let record = try? decoder.decode(PersistedChatRecord.self, from: data) else { continue }
            guard let identifier = record.sessionId ?? UUID(uuidString: record.recordId) else { continue }
            let existing = sessions[identifier]
            var accumulator = existing ?? SessionAccumulator(
                sessionId: identifier,
                name: "",
                startedAt: record.sessionStartedAt ?? record.createdAt,
                updatedAt: record.createdAt,
                observedTurns: 0,
                maxTurnIndex: 0,
                lastPrompt: record.prompt,
                lastAnswer: record.answer,
                model: record.model
            )
            if existing == nil {
                accumulator.name = record.sessionName
                    ?? fallbackSessionName(prompt: record.prompt, startedAt: accumulator.startedAt)
                accumulator.lastPrompt = record.prompt
                accumulator.lastAnswer = record.answer
                accumulator.model = record.model
            }
            accumulator.observedTurns += 1
            if let index = record.turnIndex {
                accumulator.maxTurnIndex = max(accumulator.maxTurnIndex, index)
            }
            accumulator.startedAt = min(accumulator.startedAt, record.sessionStartedAt ?? record.createdAt)
            let isNewer = record.createdAt >= accumulator.updatedAt
            accumulator.updatedAt = max(accumulator.updatedAt, record.createdAt)
            if isNewer {
                accumulator.lastPrompt = record.prompt
                accumulator.lastAnswer = record.answer
                accumulator.model = record.model
            }
            if accumulator.name.isEmpty {
                accumulator.name = record.sessionName
                    ?? fallbackSessionName(prompt: record.prompt, startedAt: accumulator.startedAt)
            }
            sessions[identifier] = accumulator
        }
        let summaries = sessions.values.map {
            CorpusSessionSummary(
                sessionId: $0.sessionId,
                name: $0.name,
                startedAt: $0.startedAt,
                updatedAt: $0.updatedAt,
                turnCount: max($0.observedTurns, $0.maxTurnIndex),
                lastPrompt: $0.lastPrompt,
                lastAnswer: $0.lastAnswer,
                model: $0.model
            )
        }
        return summaries
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private struct PersistedChatRecord: Decodable {
        let recordId: String
        let sessionId: UUID?
        let sessionName: String?
        let sessionStartedAt: Date?
        let turnIndex: Int?
        let createdAt: Date
        let prompt: String
        let answer: String
        let provider: String?
        let model: String?
    }

    private struct SessionAccumulator {
        var sessionId: UUID
        var name: String
        var startedAt: Date
        var updatedAt: Date
        var observedTurns: Int
        var maxTurnIndex: Int
        var lastPrompt: String
        var lastAnswer: String
        var model: String?
    }

    private func fallbackSessionName(prompt: String, startedAt: Date) -> String {
        let cleaned = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .prefix(8)
        if let first = components.first, !first.isEmpty {
            let joined = components.joined(separator: " ")
            if joined.count > 40 {
                let prefix = joined.prefix(39)
                return prefix + "…"
            }
            return joined
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: startedAt)
    }
}

// MARK: - Prompt Widget

struct PromptLineWidget: Widget {
    var prefix: String
    var text: String
    var cursorGlyph: Character

    func measure(in constraints: LayoutConstraints) -> LayoutSize {
        let width = prefix.count + text.count + 1
        return LayoutSize(
            width: max(constraints.minWidth, min(constraints.maxWidth, width)),
            height: 1
        )
    }

    func render(in frame: LayoutRect, buffer: inout RenderBuffer) {
        guard frame.size.width > 0 else { return }
        let available = frame.size.width
        let base = prefix + text
        let truncated = String(base.suffix(max(0, available - 1)))
        let padded = truncated.padding(toLength: max(0, available - 1), withPad: " ", startingAt: 0)
        let rendered = padded + String(cursorGlyph)
        buffer.write(rendered, at: frame.origin, maxWidth: available)
    }
}

// MARK: - Wrapping Helpers

private func wrapLineFragments(
    _ line: String,
    width: Int?,
    continuationIndent: String
) -> [String] {
    guard let width, width > 0, line.count > width else { return [line] }
    var results: [String] = []
    var start = line.startIndex
    var isFirst = true
    while start < line.endIndex {
        let available = isFirst ? width : max(1, width - continuationIndent.count)
        let end = line.index(start, offsetBy: available, limitedBy: line.endIndex) ?? line.endIndex
        var chunk = String(line[start..<end])
        if !isFirst {
            chunk = continuationIndent + chunk
        }
        results.append(chunk)
        start = end
        isFirst = false
    }
    return results
}

// MARK: - Framed Log View

struct BorderedLogView: Scene {
    var title: String
    var lines: [String]
    var maximumVisibleLines: Int
    var scrollOffset: Int

    func makeSceneNodes() -> [SceneNode] {
        [
            SceneNode(
                kind: .widget(
                    AnyWidget(
                        BorderedLogWidget(
                            title: title,
                            lines: lines,
                            maximumVisibleLines: maximumVisibleLines,
                            scrollOffset: scrollOffset
                        )
                    )
                )
            )
        ]
    }
}

private struct BorderedLogWidget: Widget {
    var title: String
    var lines: [String]
    var maximumVisibleLines: Int
    var scrollOffset: Int

    func measure(in constraints: LayoutConstraints) -> LayoutSize {
        let contentWidth = lines.map(\.count).max() ?? 0
        let width = min(constraints.maxWidth, max(constraints.minWidth, contentWidth + 2))
        let maxHeight = constraints.maxHeight == Int.max ? maximumVisibleLines + 2 : constraints.maxHeight
        let minHeight = max(constraints.minHeight, 3)
        let visibleLines = min(maximumVisibleLines, max(1, maxHeight - 2))
        let height = min(maxHeight, max(minHeight, visibleLines + 2))
        return LayoutSize(width: max(3, width), height: max(3, height))
    }

    func render(in frame: LayoutRect, buffer: inout RenderBuffer) {
        guard frame.size.width > 2, frame.size.height > 2 else { return }
        let width = frame.size.width
        let height = frame.size.height
        let topLeft = frame.origin

        let horizontal = String(repeating: "-", count: max(0, width - 2))
        buffer.write("+" + horizontal + "+", at: topLeft, maxWidth: width)
        if !title.isEmpty && width > 4 {
            let label = "[ \(title) ]"
            let truncated = String(label.prefix(max(0, width - 4)))
            buffer.write(truncated, at: LayoutPoint(x: topLeft.x + 2, y: topLeft.y), maxWidth: max(0, width - 4))
        }

        for row in 1..<(height - 1) {
            let y = topLeft.y + row
            buffer.write("|", at: LayoutPoint(x: topLeft.x, y: y), maxWidth: 1)
            buffer.write("|", at: LayoutPoint(x: topLeft.x + width - 1, y: y), maxWidth: 1)
        }

        let bottom = LayoutPoint(x: topLeft.x, y: topLeft.y + height - 1)
        buffer.write("+" + horizontal + "+", at: bottom, maxWidth: width)

        let innerWidth = width - 2
        let availableRows = height - 2
        let maxOffset = max(0, lines.count - availableRows)
        let clampedOffset = min(max(0, scrollOffset), maxOffset)
        let startIndex = max(0, lines.count - availableRows - clampedOffset)
        let endIndex = min(lines.count, startIndex + availableRows)
        let visibleLines = lines[startIndex..<endIndex]
        var currentRow = 0
        for line in visibleLines {
            guard currentRow < availableRows else { break }
            let y = topLeft.y + 1 + currentRow
            var content = String(line.prefix(innerWidth))
            if content.count < innerWidth {
                content = content.padding(toLength: innerWidth, withPad: " ", startingAt: 0)
            }
            buffer.write(content, at: LayoutPoint(x: topLeft.x + 1, y: y), maxWidth: innerWidth)
            currentRow += 1
        }
        while currentRow < availableRows {
            let y = topLeft.y + 1 + currentRow
            let blank = String(repeating: " ", count: innerWidth)
            buffer.write(blank, at: LayoutPoint(x: topLeft.x + 1, y: y), maxWidth: innerWidth)
            currentRow += 1
        }
    }
}

// MARK: - Transcript Formatter

struct TranscriptFormatter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var transcriptLimit: Int
    var wrapWidth: Int? = nil

    func lines(for snapshot: ChatSnapshot) -> [String] {
        var buffer: [String] = []
        for turn in snapshot.turns {
            let time = Self.timeFormatter.string(from: turn.createdAt)
            appendBlock(prefix: "[\(time)] You ▸ ", text: turn.prompt, into: &buffer)
            let provider = turn.provider ?? snapshot.selectedModel
            appendBlock(prefix: "[\(time)] \(provider) ▸ ", text: turn.answer, into: &buffer)
        }
        if snapshot.state == .streaming {
            let streamingText = snapshot.activeTokens.joined()
            if !streamingText.isEmpty {
                buffer.append(contentsOf: wrapLineFragments(
                    "Assistant* ▸ \(streamingText)",
                    width: wrapWidth,
                    continuationIndent: String(repeating: " ", count: "Assistant* ▸ ".count)
                ))
            }
        }
        return Array(buffer.suffix(transcriptLimit))
    }

    private func appendBlock(prefix: String, text: String, into buffer: inout [String]) {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let continuationIndent = String(repeating: " ", count: prefix.count)
        if lines.isEmpty {
            buffer.append(contentsOf: wrapLineFragments(prefix, width: wrapWidth, continuationIndent: continuationIndent))
            return
        }
        if let first = lines.first {
            buffer.append(contentsOf: wrapLineFragments(prefix + String(first), width: wrapWidth, continuationIndent: continuationIndent))
        }
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            let indented = continuationIndent + String(line)
            buffer.append(contentsOf: wrapLineFragments(indented, width: wrapWidth, continuationIndent: continuationIndent))
        }
    }
}

// MARK: - Terminal App

struct EngraverChatTUI: TerminalApp {
    private enum ScrollViewTarget: CaseIterable {
        case transcript
        case corpus
        case diagnostics
    }

    private enum EscapeSequenceState {
        case idle
        case sawEscape
        case sawBracket
        case collectingDigits(String)
    }

    var options: ChatCLIOptions
    let session: ChatSession
    var bootSequence: BootSequence?
    let desiredDiagnosticsState: Bool

    var transcriptLines: [String] = []
    var diagnosticsLines: [String] = []
    var diagnosticsBuffer: [String] = []
    var corpusLines: [String] = []
    var inputBuffer: String = ""
    var statusLine: String = "Ready"
    var showDiagnostics: Bool
    var showCorpusBrowser: Bool = false
    var lastSnapshot: ChatSnapshot?
    var lastEngDiagnosticsCount: Int = 0
    var lastTurnCount: Int = 0
    var tickCount: Int = 0
    var terminalColumns: Int = 80
    var lastCorpusRefreshTick: Int = 0
    var lastSnapshotTick: Int = 0
    var transcriptScrollOffset: Int = 0
    var diagnosticsScrollOffset: Int = 0
    var corpusScrollOffset: Int = 0
    private var escapeState: EscapeSequenceState = .idle
    private var activeScrollView: ScrollViewTarget = .transcript

    private static let corpusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let corpusRefreshStride = 20
    private let idleSnapshotStride = 3

    init(options: ChatCLIOptions, session: ChatSession, bootSequence: BootSequence?) {
        self.options = options
        self.session = session
        self.bootSequence = bootSequence
        self.desiredDiagnosticsState = options.diagnosticsInitiallyVisible
        if bootSequence != nil {
            self.showDiagnostics = true
            self.statusLine = "Booting Fountain stack…"
        } else {
            self.showDiagnostics = options.diagnosticsInitiallyVisible
        }
    }

    var banner: String { "Engraver Chat TUI" }

    var body: some Scene {
        Screen {
            VStack(spacing: 1) {
                Title("Engraver Chat Session")
                BorderedLogView(
                    title: logTitle(for: .transcript),
                    lines: transcriptLines,
                    maximumVisibleLines: options.transcriptLines,
                    scrollOffset: transcriptScrollOffset
                )
                if showCorpusBrowser {
                    BorderedLogView(
                        title: logTitle(for: .corpus),
                        lines: corpusLines,
                        maximumVisibleLines: options.corpusLines,
                        scrollOffset: corpusScrollOffset
                    )
                }
                if showDiagnostics {
                    BorderedLogView(
                        title: logTitle(for: .diagnostics),
                        lines: diagnosticsLines,
                        maximumVisibleLines: options.diagnosticsLines,
                        scrollOffset: diagnosticsScrollOffset
                    )
                }
                WidgetView(
                    PromptLineWidget(
                        prefix: promptPrefix(),
                        text: inputBuffer,
                        cursorGlyph: cursorGlyph()
                    )
                )
                StatusBar(items: statusBarItems)
            }
            .padding(1)
        }
    }

    private var statusBarItems: [StatusBar.Item] {
        [
            .label("Enter: send"),
            .label("Ctrl+C/q: quit"),
            .label("Ctrl+D: diagnostics"),
            .label("Ctrl+P: corpus"),
            .label("Ctrl+N: new chat"),
            .label("Left/Right: view"),
            .label("Up/Down PgUp/PgDn: scroll"),
            .label(statusLine)
        ]
    }

    private func displayName(for target: ScrollViewTarget) -> String {
        switch target {
        case .transcript:
            return "Transcript"
        case .corpus:
            return "Corpus"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    private func logTitle(for target: ScrollViewTarget) -> String {
        let base = displayName(for: target)
        let indicator = activeScrollView == target ? "> " : ""
        let maxOffset = maxScrollOffset(for: target)
        let offset = scrollOffset(for: target)
        let suffix: String
        if maxOffset == 0 {
            suffix = ""
        } else if offset == 0 {
            suffix = " (bottom)"
        } else if offset >= maxOffset {
            suffix = " (top)"
        } else {
            suffix = " (\(offset)/\(maxOffset))"
        }
        return indicator + base + suffix
    }

    private func lines(for target: ScrollViewTarget) -> [String] {
        switch target {
        case .transcript:
            return transcriptLines
        case .corpus:
            return corpusLines
        case .diagnostics:
            return diagnosticsLines
        }
    }

    private func visibleLineLimit(for target: ScrollViewTarget) -> Int {
        switch target {
        case .transcript:
            return options.transcriptLines
        case .corpus:
            return options.corpusLines
        case .diagnostics:
            return options.diagnosticsLines
        }
    }

    private func maxScrollOffset(for target: ScrollViewTarget) -> Int {
        let limit = max(1, visibleLineLimit(for: target))
        let total = lines(for: target).count
        return max(0, total - limit)
    }

    private func scrollOffset(for target: ScrollViewTarget) -> Int {
        switch target {
        case .transcript:
            return transcriptScrollOffset
        case .corpus:
            return corpusScrollOffset
        case .diagnostics:
            return diagnosticsScrollOffset
        }
    }

    private mutating func setScrollOffset(_ value: Int, for target: ScrollViewTarget) {
        let clamped = max(0, min(value, maxScrollOffset(for: target)))
        switch target {
        case .transcript:
            transcriptScrollOffset = clamped
        case .corpus:
            corpusScrollOffset = clamped
        case .diagnostics:
            diagnosticsScrollOffset = clamped
        }
    }

    private func isViewVisible(_ target: ScrollViewTarget) -> Bool {
        switch target {
        case .transcript:
            return true
        case .corpus:
            return showCorpusBrowser
        case .diagnostics:
            return showDiagnostics
        }
    }

    private var visibleScrollViews: [ScrollViewTarget] {
        ScrollViewTarget.allCases.filter { isViewVisible($0) }
    }

    private mutating func ensureActiveScrollViewIsVisible() {
        let available = visibleScrollViews
        guard !available.isEmpty else {
            activeScrollView = .transcript
            return
        }
        if !available.contains(activeScrollView) {
            activeScrollView = available.first ?? .transcript
        }
    }

    private mutating func focusNextScrollView() {
        let available = visibleScrollViews
        guard !available.isEmpty else { return }
        if let index = available.firstIndex(of: activeScrollView) {
            let nextIndex = (index + 1) % available.count
            activeScrollView = available[nextIndex]
        } else {
            activeScrollView = available[0]
        }
        statusLine = "\(displayName(for: activeScrollView)) focused"
    }

    private mutating func focusPreviousScrollView() {
        let available = visibleScrollViews
        guard !available.isEmpty else { return }
        if let index = available.firstIndex(of: activeScrollView) {
            let previousIndex = (index - 1 + available.count) % available.count
            activeScrollView = available[previousIndex]
        } else {
            activeScrollView = available[0]
        }
        statusLine = "\(displayName(for: activeScrollView)) focused"
    }

    private mutating func scroll(_ target: ScrollViewTarget, by delta: Int) {
        guard delta != 0 else { return }
        let maxOffset = maxScrollOffset(for: target)
        let current = scrollOffset(for: target)
        let updated = max(0, min(maxOffset, current + delta))
        if updated != current {
            setScrollOffset(updated, for: target)
        }
        reportScrollChange(for: target)
    }

    private mutating func pageScroll(_ target: ScrollViewTarget, direction: Int) {
        guard direction != 0 else { return }
        let step = max(1, visibleLineLimit(for: target) - 1)
        scroll(target, by: step * direction)
    }

    private mutating func scrollToTop(_ target: ScrollViewTarget) {
        let maxOffset = maxScrollOffset(for: target)
        setScrollOffset(maxOffset, for: target)
        reportScrollChange(for: target)
    }

    private mutating func scrollToBottom(_ target: ScrollViewTarget) {
        setScrollOffset(0, for: target)
        reportScrollChange(for: target)
    }

    private mutating func reportScrollChange(for target: ScrollViewTarget) {
        let name = displayName(for: target)
        let maxOffset = maxScrollOffset(for: target)
        let offset = min(scrollOffset(for: target), maxOffset)
        let message: String
        if maxOffset == 0 {
            message = "\(name) showing latest lines"
        } else if offset == 0 {
            message = "\(name) at bottom"
        } else if offset >= maxOffset {
            message = "\(name) at top"
        } else {
            message = "\(name) offset \(offset)/\(maxOffset)"
        }
        statusLine = message
    }

    private mutating func clampScrollOffsets() {
        setScrollOffset(transcriptScrollOffset, for: .transcript)
        setScrollOffset(diagnosticsScrollOffset, for: .diagnostics)
        setScrollOffset(corpusScrollOffset, for: .corpus)
    }

    mutating func onEvent(_ event: Event, context: AppContext) async {
        switch event {
        case .tick:
            if let size = context.terminalSize {
                terminalColumns = size.columns
            }
            tickCount += 1
            await pollBoot()
            await refreshSnapshot(force: false)
        case let .key(.character(character)):
            await handle(character: character, context: context)
        }
    }

    // MARK: - Event Handling

    private mutating func handle(character: Character, context: AppContext) async {
        switch escapeState {
        case .idle:
            if character == "\u{1B}" {
                escapeState = .sawEscape
                return
            }
            await handleBaseCharacter(character, context: context)
        case .sawEscape:
            if character == "[" {
                escapeState = .sawBracket
                return
            }
            escapeState = .idle
            await handleBaseCharacter(character, context: context)
        case .sawBracket:
            if character.isNumber {
                escapeState = .collectingDigits(String(character))
                return
            }
            escapeState = .idle
            handleEscapeCommand(character)
        case .collectingDigits(let digits):
            if character.isNumber {
                escapeState = .collectingDigits(digits + String(character))
                return
            }
            escapeState = .idle
            if character == "~" {
                handleBracketNumberSequence(digits)
            } else {
                await handleBaseCharacter(character, context: context)
            }
        }
    }

    private mutating func handleEscapeCommand(_ character: Character) {
        switch character {
        case "A":
            scroll(activeScrollView, by: 1)
        case "B":
            scroll(activeScrollView, by: -1)
        case "C":
            focusNextScrollView()
        case "D":
            focusPreviousScrollView()
        case "H":
            scrollToTop(activeScrollView)
        case "F":
            scrollToBottom(activeScrollView)
        case "Z":
            focusPreviousScrollView()
        default:
            break
        }
    }

    private mutating func handleBracketNumberSequence(_ digits: String) {
        switch digits {
        case "5":
            pageScroll(activeScrollView, direction: 1)
        case "6":
            pageScroll(activeScrollView, direction: -1)
        case "1":
            scrollToTop(activeScrollView)
        case "4":
            scrollToBottom(activeScrollView)
        default:
            break
        }
    }

    private mutating func handleBaseCharacter(_ character: Character, context: AppContext) async {
        let scalar = character.unicodeScalars.first?.value ?? 0

        switch scalar {
        case 3, 17:
            await context.quit()
            return
        case 4:
            showDiagnostics.toggle()
            if showDiagnostics {
                refreshDiagnosticsLines()
                setScrollOffset(0, for: .diagnostics)
                activeScrollView = .diagnostics
            }
            clampScrollOffsets()
            ensureActiveScrollViewIsVisible()
            statusLine = showDiagnostics ? "Diagnostics visible" : "Diagnostics hidden"
            return
        case 9:
            focusNextScrollView()
            return
        case 14:
            await startNewChat()
            return
        case 16:
            showCorpusBrowser.toggle()
            if showCorpusBrowser {
                setScrollOffset(0, for: .corpus)
                lastCorpusRefreshTick = 0
                await refreshCorpusView(force: true)
                activeScrollView = .corpus
            }
            clampScrollOffsets()
            ensureActiveScrollViewIsVisible()
            statusLine = showCorpusBrowser ? "Corpus browser visible" : "Corpus browser hidden"
            return
        case 21:
            inputBuffer.removeAll(keepingCapacity: false)
            return
        case 23:
            await session.cancel()
            statusLine = "Cancelled streaming turn"
            return
        default:
            break
        }

        if character == "q" || character == "Q" {
            await context.quit()
            return
        }

        if character == "\u{7f}" || character == "\u{8}" {
            if !inputBuffer.isEmpty {
                inputBuffer.removeLast()
            }
            return
        }

        if character == "\n" || character == "\r" {
            await submitCurrentInput()
            return
        }

        guard scalar >= 32 else { return }
        inputBuffer.append(character)
    }

    private mutating func submitCurrentInput() async {
        let trimmed = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputBuffer.removeAll(keepingCapacity: false)
        if bootSequence == nil {
            statusLine = "Sending prompt…"
        }
        await session.submit(prompt: trimmed)
        await refreshSnapshot(force: true)
    }

    private mutating func startNewChat() async {
        await session.startNewSession()
        inputBuffer.removeAll(keepingCapacity: false)
        transcriptLines.removeAll(keepingCapacity: false)
        diagnosticsBuffer.removeAll(keepingCapacity: false)
        diagnosticsLines.removeAll(keepingCapacity: false)
        corpusLines.removeAll(keepingCapacity: false)
        lastSnapshot = nil
        lastEngDiagnosticsCount = 0
        lastTurnCount = 0
        lastSnapshotTick = 0
        lastCorpusRefreshTick = 0
        transcriptScrollOffset = 0
        diagnosticsScrollOffset = 0
        corpusScrollOffset = 0
        escapeState = .idle
        activeScrollView = .transcript
        statusLine = "Started new chat session"
        await refreshSnapshot(force: true)
        if showCorpusBrowser {
            await refreshCorpusView(force: true)
        }
    }

    // MARK: - Snapshot & Diagnostics

    private mutating func pollBoot() async {
        guard let bootSequence else { return }
        let update = await bootSequence.poll()
        if !update.newLines.isEmpty {
            appendDiagnostics(update.newLines)
        }
        if update.completed {
            self.bootSequence = nil
            if let code = update.exitCode, code != 0 {
                appendDiagnostics(["[boot] dev-up exited with code \(code)."])
                statusLine = "Boot failed (code \(code))"
            } else {
                statusLine = "Boot complete"
            }
            showDiagnostics = desiredDiagnosticsState || !diagnosticsBuffer.isEmpty
        } else {
            statusLine = "Booting Fountain stack…"
        }
        if showDiagnostics {
            refreshDiagnosticsLines()
        }
    }

    private mutating func refreshSnapshot(force: Bool) async {
        if !force {
            let shouldThrottle = lastSnapshotTick != 0 && (tickCount - lastSnapshotTick) < idleSnapshotStride
            let isStreaming = lastSnapshot?.state == .streaming
            if shouldThrottle && !isStreaming {
                return
            }
        }
        lastSnapshotTick = tickCount

        let previousTurnCount = lastTurnCount
        let snapshot = await session.snapshot()
        lastSnapshot = snapshot
        lastTurnCount = snapshot.turns.count
        let turnCountChanged = snapshot.turns.count != previousTurnCount

        let formatter = TranscriptFormatter(
            transcriptLimit: options.transcriptLines,
            wrapWidth: transcriptWrapWidth
        )
        transcriptLines = formatter.lines(for: snapshot)
        clampScrollOffsets()

        if snapshot.diagnostics.count > lastEngDiagnosticsCount {
            let newEntries = snapshot.diagnostics[lastEngDiagnosticsCount..<snapshot.diagnostics.count]
            appendDiagnostics(Array(newEntries))
            lastEngDiagnosticsCount = snapshot.diagnostics.count
        }

        if showDiagnostics {
            refreshDiagnosticsLines()
        }

        if case .failed = snapshot.state, !showDiagnostics {
            showDiagnostics = true
            refreshDiagnosticsLines()
        }

        if showCorpusBrowser {
            await refreshCorpusView(force: turnCountChanged)
        }

        if bootSequence == nil {
            statusLine = status(from: snapshot)
        }
    }

    private func status(from snapshot: ChatSnapshot) -> String {
        var parts: [String] = []
        parts.append("model: \(snapshot.selectedModel)")
        parts.append("state: \(describe(state: snapshot.state))")
        parts.append("corpus: \(snapshot.corpusId)/\(snapshot.collection)")
        parts.append("session: \(sessionDisplayName(snapshot))")
        if let error = snapshot.lastError, !error.isEmpty {
            parts.append("error: \(truncate(error, limit: 120))")
        }
        return parts.joined(separator: "  ")
    }

    private func describe(state: EngraverChatState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .streaming:
            return "streaming"
        case .failed(let message):
            return "failed(\(truncate(message, limit: 24)))"
        }
    }

    private func cursorGlyph() -> Character {
        (tickCount % 2 == 0) ? "_" : " "
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit - 1)
        return prefix + "…"
    }

    private func promptPrefix() -> String {
        "You > "
    }

    private func sessionDisplayName(_ snapshot: ChatSnapshot) -> String {
        if let name = snapshot.sessionName, !name.isEmpty {
            return truncate(name, limit: 24)
        }
        return String(snapshot.sessionId.uuidString.prefix(8))
    }

    private mutating func appendDiagnostics<S: Sequence>(_ entries: S) where S.Element == String {
        let width = diagnosticWrapWidth
        for entry in entries {
            diagnosticsBuffer.append(contentsOf: wrapDiagnostic(entry, width: width))
        }
    }

    private mutating func refreshDiagnosticsLines() {
        diagnosticsLines = Array(diagnosticsBuffer.suffix(options.diagnosticsLines))
        clampScrollOffsets()
    }

    private mutating func refreshCorpusView(force: Bool) async {
        guard showCorpusBrowser else { return }
        if !force, (tickCount - lastCorpusRefreshTick) < corpusRefreshStride {
            return
        }
        lastCorpusRefreshTick = tickCount
        let persistenceAvailable = await session.persistenceEnabled()
        guard persistenceAvailable else {
            corpusLines = [
                "Corpus browser",
                "  Persistence disabled (ENGRAVER_DISABLE_PERSISTENCE=true)"
            ]
            clampScrollOffsets()
            return
        }
        if lastSnapshot == nil {
            lastSnapshot = await session.snapshot()
        }
        do {
            let fetchLimit = max(options.corpusLines, 5)
            let sessions = try await session.fetchCorpusSessions(limit: fetchLimit)
            corpusLines = formatCorpusSessions(sessions, snapshot: lastSnapshot)
            clampScrollOffsets()
        } catch {
            let message = truncate(error.localizedDescription, limit: max(24, corpusWrapWidth - 4))
            corpusLines = [
                "Corpus browser",
                "  Fetch failed: \(message)"
            ]
            clampScrollOffsets()
        }
    }

    private func formatCorpusSessions(_ sessions: [CorpusSessionSummary], snapshot: ChatSnapshot?) -> [String] {
        let corpusId = snapshot?.corpusId ?? "(unknown corpus)"
        let collection = snapshot?.collection ?? "(unknown collection)"
        var lines: [String] = []
        let header = "Corpus: \(corpusId)/\(collection) — sessions"
        lines.append(contentsOf: wrapLineFragments(header, width: corpusWrapWidth, continuationIndent: "  "))
        guard !sessions.isEmpty else {
            lines.append("  (no chat sessions yet)")
            return Array(lines.prefix(options.corpusLines))
        }
        for session in sessions {
            let turnsLabel = session.turnCount == 1 ? "1 turn" : "\(session.turnCount) turns"
            let time = Self.corpusTimeFormatter.string(from: session.updatedAt)
            let nameLine = "• \(session.name)  (\(turnsLabel), last \(time))"
            lines.append(contentsOf: wrapLineFragments(nameLine, width: corpusWrapWidth, continuationIndent: "  "))
            let promptSnippet = corpusSnippet(session.lastPrompt, limit: 60)
            if !promptSnippet.isEmpty {
                let promptLine = "  ↳ Prompt: \(promptSnippet)"
                lines.append(contentsOf: wrapLineFragments(promptLine, width: corpusWrapWidth, continuationIndent: "    "))
            }
            let answerSnippet = corpusSnippet(session.lastAnswer, limit: 60)
            if !answerSnippet.isEmpty {
                let answerLine = "  ↳ Reply: \(answerSnippet)"
                lines.append(contentsOf: wrapLineFragments(answerLine, width: corpusWrapWidth, continuationIndent: "    "))
            }
        }
        return Array(lines.prefix(options.corpusLines))
    }

    private func corpusSnippet(_ text: String, limit: Int) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "" }
        let components = singleLine
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let collapsed = components.joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }
        return truncate(collapsed, limit: limit)
    }

    private var contentWrapWidth: Int {
        max(8, terminalColumns - 8)
    }

    private var transcriptWrapWidth: Int {
        max(20, contentWrapWidth)
    }

    private var diagnosticWrapWidth: Int {
        max(20, contentWrapWidth)
    }

    private var corpusWrapWidth: Int {
        max(20, contentWrapWidth)
    }

    private func wrapDiagnostic(_ entry: String, width: Int) -> [String] {
        guard width > 0 else { return [entry] }
        let segments = entry.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if segments.isEmpty {
            return [""]
        }
        return segments.flatMap { wrapDiagnosticSegment($0, width: width) }
    }

    private func wrapDiagnosticSegment(_ segment: Substring, width: Int) -> [String] {
        guard !segment.isEmpty else { return [""] }
        let indent = "  "
        return wrapLineFragments(String(segment), width: width, continuationIndent: indent)
    }
}

// MARK: - Boot Helpers

private func locateDevUpScript() -> URL? {
    let fm = FileManager.default
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<6 {
        let candidate = url.appendingPathComponent("Scripts/dev-up")
        if fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        url.deleteLastPathComponent()
    }
    return nil
}

// MARK: - Entry Point

@main
enum EngraverChatTUIMain {
    static func main() async {
        switch ChatCLIOptions.parse(CommandLine.arguments) {
        case .help:
            print(ChatCLICommand.helpText)
            return
        case let .run(options):
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in options.overrides {
                environment[key] = value
            }
            if options.disablePersistence {
                environment["ENGRAVER_DISABLE_PERSISTENCE"] = "true"
            }
            populateFountainSecrets(into: &environment)

            let scriptURL = locateDevUpScript()
            let bootSequence = await BootSequence.start(scriptURL: scriptURL, environment: environment)
            let configuration = EngraverStudioConfiguration(environment: environment)
            let session = await ChatSession(configuration: configuration)

            if options.previewOnly {
                let snapshot = await session.snapshot()
                let formatter = TranscriptFormatter(
                    transcriptLimit: options.transcriptLines,
                    wrapWidth: 72
                )
                let lines = formatter.lines(for: snapshot)
                print(lines.joined(separator: "\n"))
                return
            }

            let app = EngraverChatTUI(options: options, session: session, bootSequence: bootSequence)
            do {
                _ = try await app.run()
            } catch {
                let message = "Failed to launch Engraver Chat TUI: \(error)\n"
                if let data = message.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
                exit(1)
            }
        }
    }
}

private func populateFountainSecrets(into environment: inout [String: String]) {
    if (environment["GATEWAY_BEARER"]?.isEmpty ?? true),
       let secret = SecretStoreHelper.read(service: "FountainAI", account: "GATEWAY_BEARER") {
        environment["GATEWAY_BEARER"] = secret
    }
    if (environment["OPENAI_API_KEY"]?.isEmpty ?? true),
       let apiKey = SecretStoreHelper.read(service: "FountainAI", account: "OPENAI_API_KEY") {
        environment["OPENAI_API_KEY"] = apiKey
    }
}
