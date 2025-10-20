import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif
import Combine
import FountainStoreClient
import FountainAIKit
import ProviderOpenAI
import ProviderGateway
import ApiClientsCore
import AwarenessAPI
import FountainAICore
// Avoid importing generator/runtime directly here to reduce package fan-out.
// We will use a minimal URLSession-based client to call the Semantic Browser's
// query endpoints according to the curated OpenAPI spec.
import SemanticBrowserAPI
import OpenAPIURLSession
import ApiClientsCore
import OpenAPIRuntime
import FountainRuntime

/// Public facade for embedding MemChat in host apps.
/// Wraps EngraverChatViewModel and enforces per-chat corpus isolation while
/// retrieving memory from a selected corpus.
@MainActor
public final class MemChatController: ObservableObject {
    public private(set) var config: MemChatConfiguration

    // Expose a subset of EngraverChatViewModel for host apps.
    @Published public private(set) var turns: [EngraverChatTurn] = []
    @Published public private(set) var streamingText: String = ""
    @Published public private(set) var streamingTokens: [String] = []
    @Published public private(set) var state: EngraverChatState = .idle
    @Published public private(set) var chatCorpusId: String
    @Published public private(set) var corpusTitle: String? = nil
    @Published public private(set) var chatTitle: String? = nil
    @Published public private(set) var providerLabel: String = ""
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var memoryTrail: [String] = []
    @Published public private(set) var lastInjectedContext: InjectedContext? = nil
    @Published public private(set) var turnContext: [UUID: InjectedContext] = [:]
    @Published public private(set) var sessionOverviews: [CorpusSessionOverview] = []
    @Published public private(set) var learnProgress: LearnProgress? = nil
    @Published public private(set) var semanticPanel: SemanticPanel? = nil
    @Published public private(set) var recentEvidence: [CitedSegmentEvidence] = []
    @Published public private(set) var calculusReport: GenerationReport? = nil

    private let vm: EngraverChatViewModel
    private let store: FountainStoreClient
    private var continuityDigest: String? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var didAutoBaseline: Bool = false
    private var pendingContext: InjectedContext? = nil
    private var lastBaselineText: String? = nil
    private var analysisCounter: Int = 0
    private let browserConfig: SeedingConfiguration.Browser?
    private var lastArtifactsByHost: [String: Date] = [:]

    public struct InjectedContext: Sendable, Equatable {
        public let continuity: String?
        public let awarenessSummary: String?
        public let awarenessHistory: String?
        public let snippets: [String]
        public let baselines: [String]
        public let drifts: [String]
        public let patterns: [String]
    }

    public struct SemanticPanel: Sendable, Equatable {
        public struct Source: Sendable, Equatable, Identifiable { public let id: String; public let title: String }
        public let topicName: String?
        public let topicType: String?
        public let sources: [Source]
        public let stepstones: [String]
    }
    public struct LearnProgress: Sendable, Equatable { public let visited: Int; public let pages: Int; public let segs: Int; public let target: Int }
    public struct CitedSegmentEvidence: Sendable, Equatable, Identifiable { public let id: String; public let title: String; public let url: String; public let text: String }
    public struct GenerationReport: Sendable, Equatable {
        public enum Source: String, Sendable { case user, model, deterministic }
        public let baselineSource: Source
        public let driftSource: Source
        public let patternsSource: Source
        public let reflectionSource: Source
        public let evidenceCount: Int
        public let baselineLength: Int
        public let driftLines: Int
        public let patternsLines: Int
    }

    public struct BaselineItem: Sendable, Identifiable, Equatable {
        public let id: String
        public let content: String
        public let ts: Double
    }

    public struct DriftItem: Sendable, Identifiable, Equatable {
        public let id: String
        public let content: String
        public let ts: Double
    }

    public struct PatternsItem: Sendable, Identifiable, Equatable {
        public let id: String
        public let content: String
        public let ts: Double
    }

    public struct HostCoverageItem: Sendable, Identifiable, Equatable {
        public var id: String { host }
        public let host: String
        public let pages: Int
        public let segments: Int
        public struct Source: Sendable, Equatable { public let title: String; public let url: String }
        public let recent: [Source]
    }

    public init(
        config: MemChatConfiguration,
        store: FountainStoreClient? = nil,
        chatClientOverride: ChatStreaming? = nil
    ) {
        self.config = config
        self.chatCorpusId = Self.makeChatCorpusId()

        // Resolve store: prefer on-disk FountainStore for full persistence.
        // If disk initialisation fails, fall back to embedded to keep the chat usable.
        let svc: FountainStoreClient
        if let store { svc = store }
        else if let disk = Self.makeDiskStoreClient() {
            svc = FountainStoreClient(client: disk)
        } else {
            svc = FountainStoreClient(client: EmbeddedFountainStoreClient())
            print("[MemChatKit] Warning: DiskFountainStoreClient unavailable; using in-memory store.")
        }

        // Resolve chat client: prefer Gateway when configured; else direct OpenAI provider
        let useGateway = (config.gatewayURL != nil) && (chatClientOverride == nil)
        let chatClient: ChatStreaming
        if useGateway, let url = config.gatewayURL {
            let gateway = GatewayProvider.make(baseURL: url) { nil }
            chatClient = gateway
        } else {
            let provider = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                           openAIEndpoint: config.openAIEndpoint,
                                                           localEndpoint: config.localCompatibleEndpoint)
            let selectedEndpoint = provider?.endpoint ?? ProviderResolver.openAIChatURL
            let defaultClient = OpenAICompatibleChatProvider(apiKey: provider?.usesAPIKey == true ? config.openAIAPIKey : nil,
                                                             endpoint: selectedEndpoint)
            chatClient = chatClientOverride ?? defaultClient
        }

        // Seeding/memory config to point at standard collections
        let browser = SeedingConfiguration.Browser(
            baseURL: URL(string: ProcessInfo.processInfo.environment["SEMANTIC_BROWSER_URL"] ?? "http://127.0.0.1:8007")!,
            apiKey: nil,
            mode: .quick,
            defaultLabels: [],
            pagesCollection: "pages",
            segmentsCollection: "segments",
            entitiesCollection: "entities",
            tablesCollection: "tables",
            storeOverride: nil
        )
        // Keep seeding configuration defined (for optional ingestion flows), but runtime snippet retrieval
        // no longer reaches out to the Semantic Browser; it uses FountainStore exclusively.
        let seeding = SeedingConfiguration(sources: [], browser: browser)
        self.browserConfig = browser

        self.store = svc
        vm = EngraverChatViewModel(
            chatClient: chatClient,
            persistenceStore: svc,
            corpusId: config.memoryCorpusId, // read memory from here
            collection: config.chatCollection,
            availableModels: [config.model],
            defaultModel: config.model,
            debugEnabled: false,
            awarenessBaseURL: config.awarenessURL,
            bootstrapBaseURL: config.bootstrapURL,
            bearerToken: nil,
            seedingConfiguration: seeding,
            environmentController: nil,
            semanticSeeder: SemanticBrowserSeeder(),
            gatewayBaseURL: config.gatewayURL ?? URL(string: "http://127.0.0.1:8010")!,
            directMode: !useGateway
        )

        // Bind outputs
        vm.$turns.sink { [weak self] newTurns in
            guard let self else { return }
            let oldCount = self.turns.count
            self.turns = newTurns
            if let last = newTurns.last, newTurns.count > oldCount {
                if let ctx = self.pendingContext {
                    self.turnContext[last.id] = ctx
                    self.lastInjectedContext = ctx
                    self.pendingContext = nil
                }
                Task { await self.persistReflection(from: last) }
                Task { await self.tryAutoBaseline(from: last) }
                analysisCounter += 1
                if analysisCounter >= 3 { analysisCounter = 0; Task { await self.tryAutoPatternsAndDrift() } }
                Task { await self.suggestChatTitle(from: last) }
            }
        }.store(in: &cancellables)
        vm.$activeTokens
            .removeDuplicates()
            .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
            .sink { [weak self] tokens in
                guard let self else { return }
                self.streamingTokens = tokens
                self.streamingText = tokens.joined()
            }
            .store(in: &cancellables)
        vm.$state.sink { [weak self] s in self?.state = s }.store(in: &cancellables)
        vm.$lastError.sink { [weak self] e in self?.lastError = e }.store(in: &cancellables)
        vm.$corpusSessionOverviews.sink { [weak self] list in self?.sessionOverviews = list }.store(in: &cancellables)
        vm.$sessionName.sink { [weak self] name in self?.chatTitle = name }.store(in: &cancellables)

        Task {
            await self.loadContinuityDigest()
            await self.generateCorpusTitle()
            if self.config.awarenessURL != nil {
                await self.refreshAwareness(reason: "init")
            }
            if self.config.bootstrapURL != nil {
                // Kick Bootstrap once at startup to ensure corpus roles, defaults, and collections exist.
                await MainActor.run { self.vm.rerunBootstrap() }
            }
            if self.config.gatewayURL != nil {
                await self.ensureRolesViaGateway()
            }
        }
        // Provider label
        self.providerLabel = useGateway ? "gateway" : "openai"
    }

    public func newChat() {
        chatCorpusId = Self.makeChatCorpusId()
        vm.startNewSession()
    }

    public func setStrictMemoryMode(_ enabled: Bool) {
        self.config.strictMemoryMode = enabled
    }

    public func setDeepSynthesis(_ enabled: Bool) {
        self.config.deepSynthesis = enabled
    }

    public func setDepthLevel(_ level: Int) {
        self.config.depthLevel = max(1, min(level, 3))
    }

    /// Purge and recreate the configured memory corpus, clearing all pages, chats, and artifacts.
    /// Returns true on success.
    public func resetMemoryCorpus() async -> Bool {
        do {
            // Delete then recreate
            try? await store.deleteCorpus(config.memoryCorpusId)
            _ = try await store.createCorpus(config.memoryCorpusId)
            // Also purge Awareness corpus if configured, then re-init
            if let base = config.awarenessURL {
                do {
                    let client = AwarenessClient(baseURL: base)
                    try await client.deleteCorpus(corpusID: config.memoryCorpusId)
                    _ = try? await client.initializeCorpus(.init(corpusId: config.memoryCorpusId))
                    logTrail("awareness purge ok")
                } catch {
                    logTrail("awareness purge error • \(error)")
                }
            }
            // Reset local state
            await MainActor.run {
                self.turns = []
                self.streamingText = ""
                self.streamingTokens = []
                self.sessionOverviews = []
                self.memoryTrail.removeAll(keepingCapacity: false)
                self.lastInjectedContext = nil
                self.turnContext = [:]
                self.corpusTitle = nil
                self.chatTitle = nil
                self.recentEvidence = []
                self.didAutoBaseline = false
                self.lastBaselineText = nil
                self.chatCorpusId = Self.makeChatCorpusId()
                self.vm.startNewSession()
            }
            logTrail("corpus reset ok • id=\(config.memoryCorpusId)")
            if self.config.awarenessURL != nil {
                await self.refreshAwareness(reason: "reset")
            }
            return true
        } catch {
            await MainActor.run { self.lastError = "Reset failed: \(error)" }
            logTrail("corpus reset error • \(error)")
            return false
        }
    }

public func openChatSession(_ id: UUID) {
    vm.openPersistedSession(id: id)
}

    public func send(_ text: String) {
        // Deep Answer Mode: build a compact FactPack and compose strictly from it
        if config.deepSynthesis {
            Task { [weak self] in
                await self?.sendDeep(text)
            }
            return
        }
        var base: [String] = []
        if let digest = continuityDigest, !digest.isEmpty {
            base.append("ContinuityDigest: \(digest)")
        }
        Task { [weak self] in
            guard let self else { return }
            // Ensure Awareness context is fresh and inject summaries
            if self.config.awarenessURL != nil {
                await self.ensureAwarenessContext()
                if let summary = self.vm.awarenessSummaryText, !summary.isEmpty {
                    base.append("Awareness Summary: \(self.trim(summary, limit: 600))")
                }
                if let history = self.vm.awarenessHistorySummary, !history.isEmpty {
                    base.append("History Overview: \(self.trim(history, limit: 600))")
                }
            }

            // Retrieve memory snippets (with a broad fallback) and recent baselines/drifts/patterns
            let requestedURL = self._extractURLOrDomain(from: text)
            let host = requestedURL?.host
            let snippetDetails = await self.retrieveMemorySnippetDetails(matching: text, limit: 5)
            var snippets = await self.retrieveMemorySnippets(matching: text, limit: 5)
            // If asking about a specific host and no matches on plain text search, try host-targeted retrieval
            if snippets.isEmpty, let h = host {
                let hostSnips = await self.retrieveHostSnippets(host: h, limit: 5)
                if !hostSnips.isEmpty { snippets = hostSnips }
            }
            // If we appear to be asked about a specific site and nothing is found, try to ingest then re-query.
            if snippets.isEmpty, let url = requestedURL {
                self.logTrail("autofetch: \(url.absoluteString)")
                _ = await self.ingestURLAdvanced(url, modeLabel: "standard", sameDomainDepth: 1)
                snippets = await self.retrieveMemorySnippets(matching: text, limit: 5)
                if snippets.isEmpty, let h = host { snippets = await self.retrieveHostSnippets(host: h, limit: 5) }
            }
            if snippets.isEmpty { snippets = await self.retrieveMemorySnippets(matching: "", limit: 5) }
            let baselines = await self.retrieveRecentBaselines(limit: 6)
            let drifts = await self.retrieveRecentDrifts(limit: 3)
            let patterns = await self.retrieveRecentPatterns(limit: 2)

            var enriched = base
            // Grounding/answering policy to avoid generic internet disclaimers.
            enriched.append("""
            AnsweringPolicy:
            - Use the provided Memory snippets and context as your knowledge base.
            - Do not claim that you lack internet or browsing; you are answering from the local memory corpus.
            - If the requested fact is not present in memory, say "I don’t have that in memory" and offer to refine.
            - Prefer concise, factual responses; no speculation.
            - For time-sensitive topics (e.g., "news today"), summarize what is present in memory without claiming live status; mention that it reflects the stored snapshot.
            """)
            let asksBaselines = Self._baselineIntent(in: text)
            if let h = host {
                // When we have host coverage, make the directive explicit and include recent page titles for stronger grounding.
                let cov = await self.fetchHostCoverage(host: h, limit: 8)
                if cov.pages > 0 {
                    // Ensure persisted artifacts exist so we have concrete memory payloads
                    await self.ensureHostMemoryArtifacts(host: h)
                    let recents = cov.recent.map { "• \($0.title) — \($0.url)" }.joined(separator: "\n")
                    if config.strictMemoryMode {
                        if config.deepSynthesis {
                            enriched.append("""
                    MemoryCoverage(host=\(h))
                    - Pages: \(cov.pages)
                    - Segments: \(cov.segments)
                    - Recent pages:\n\(recents)
                    OutputPolicy (Deep):
                    - Produce a multi-section brief titled "As of our stored snapshot of \(h)".
                    - 3–5 sections; each section has 2–4 bullets.
                    - Every bullet MUST end with a citation [Title](URL) from the evidence.
                    - Prefer specificity over generalities; avoid hedging.
                    """)
                        } else {
                            enriched.append("""
                    MemoryCoverage(host=\(h))
                    - Pages: \(cov.pages)
                    - Segments: \(cov.segments)
                    - Recent pages:\n\(recents)
                    OutputPolicy:
                    - Do NOT say "I don't have that in memory".
                    - Instead say: "As of our stored snapshot of \(h), here is the current overview:" then give 6–9 bullets.
                    - Every bullet MUST end with a citation [Title](URL) from the evidence.
                    - Prefer specificity over generalities; avoid hedging.
                    """)
                        }
                    }
                }
            }
            // If strict mode with host context, prefer explicit evidence packet
            if let h = host, config.strictMemoryMode {
                let evidence = await self.fetchCitedEvidence(host: h, depthLevel: self.config.depthLevel)
                let cited = evidence.map { "• \(self.trim($0.text, limit: 300)) — [\(self.trim($0.title, limit: 120))](\($0.url))" }
                if !cited.isEmpty {
                    enriched.append("Evidence Packet (host=\(h)):\n" + cited.joined(separator: "\n"))
                    await MainActor.run {
                        self.recentEvidence = evidence.enumerated().map { idx, e in
                            CitedSegmentEvidence(id: "ev-\(idx)", title: e.title, url: e.url, text: self.trim(e.text, limit: 400))
                        }
                    }
                }
            }
            // If the user is asking about baselines, make the instruction explicit and inject them verbatim
            if asksBaselines {
                // For explicit baseline requests, force a verbatim response.
                // Build a numbered block locally and require exact reproduction.
                let verbatim: String = {
                    if baselines.isEmpty { return "No baselines stored." }
                    return baselines.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")
                }()
                let policy = """
                BaselineAnsweringPolicy (VERBATIM):
                - Your entire reply MUST be exactly the Baselines block below, nothing else.
                - Do not paraphrase or add introductions; keep numbering and text unchanged.
                - If the block reads "No baselines stored.", reply exactly that.
                """
                enriched.append(policy)
                enriched.append("Baselines:\n" + verbatim)
                logTrail("baseline.verbatim • count=\(baselines.count)")
            }
            if !snippets.isEmpty && !(config.strictMemoryMode && host != nil) {
                // If we have richer snippet details with pageIds, prefer a cited list
                var cited: [String] = []
                if !snippetDetails.isEmpty {
                    for d in snippetDetails {
                        if let pid = d.pageId, let meta = await self.fetchPageMeta(pageId: pid) {
                            cited.append("• \(d.text) — [\(meta.title)](\(meta.url))")
                        } else {
                            cited.append("• \(d.text)")
                        }
                    }
                } else {
                    cited = snippets.map { "• \($0)" }
                }
                let list = cited.joined(separator: "\n")
                enriched.append("Memory snippets (from corpus \(self.config.memoryCorpusId)):\n\(list)")
                self.logTrail("MEMORY inject • snippets=\(snippets.count) summary=\(self.vm.awarenessSummaryText?.count ?? 0)")
            } else {
                self.logTrail("MEMORY inject • snippets=0 summary=\(self.vm.awarenessSummaryText?.count ?? 0)")
            }
            if let h = host, !(config.strictMemoryMode), let hostSummary = await self.buildHostSnapshotIfAvailable(host: h) {
                enriched.append(hostSummary)
            }
            if !baselines.isEmpty && !asksBaselines {
                let block = await self.condenseList(header: "Baselines", items: baselines, budget: 2000)
                enriched.append(block)
                self.logTrail("MEMORY inject • baselines=\(baselines.count)")
            }
            if !drifts.isEmpty && !(config.strictMemoryMode && host != nil) && !asksBaselines {
                let block = await self.condenseList(header: "Recent Drift", items: drifts, budget: 1600)
                enriched.append(block)
                self.logTrail("MEMORY inject • drifts=\(drifts.count)")
            }
            if !patterns.isEmpty && !(config.strictMemoryMode && host != nil) && !asksBaselines {
                let block = await self.condenseList(header: "Patterns", items: patterns, budget: 1600)
                enriched.append(block)
                self.logTrail("MEMORY inject • patterns=\(patterns.count)")
            }

            // Publish inspector context
            let ctx = InjectedContext(
                continuity: self.continuityDigest,
                awarenessSummary: self.vm.awarenessSummaryText,
                awarenessHistory: self.vm.awarenessHistorySummary,
                snippets: snippets,
                baselines: baselines,
                drifts: drifts,
                patterns: patterns
            )
            self.lastInjectedContext = ctx
            self.pendingContext = ctx

            if self.config.showSemanticPanel {
                let panel = await self.buildSemanticPanel(from: snippetDetails, baselines: baselines, patterns: patterns)
                await MainActor.run { self.semanticPanel = panel }
            }

            let sys = self.vm.makeSystemPrompts(base: enriched)
            await MainActor.run {
                // Persist chats into the configured memory corpus so past sessions
                // are discoverable and listable. No per-chat corpus override.
                self.vm.send(prompt: text, systemPrompts: sys, preferStreaming: true, corpusOverride: nil)
            }
        }
    }

    /// Deep Answer Mode: build a compact FactPack from the memory corpus and
    /// compose the final answer strictly from those facts. Prefer the Gateway
    /// provider when configured; fall back to direct provider otherwise via the
    /// existing EngraverChatViewModel routing. This keeps streaming/persistence intact.
    private func sendDeep(_ text: String) async {
        logTrail("deep-mode: assembling factpack")
        var policy: [String] = []
        if let digest = continuityDigest, !digest.isEmpty {
            policy.append("ContinuityDigest: \(digest)")
        }

        // Ensure Awareness context is fresh (best-effort)
        if config.awarenessURL != nil { await ensureAwarenessContext() }

        // Derive host intent and collect evidence/facts
        let requestedURL = _extractURLOrDomain(from: text)
        let host = requestedURL?.host

        // Fetch snippets/evidence and recent artifacts deterministically
        var snippetDetails = await retrieveMemorySnippetDetails(matching: text, limit: 8)
        if snippetDetails.isEmpty, let url = requestedURL {
            // Auto-ingest a small slice if nothing is present yet for this host
            logTrail("autofetch(deep): \(url.absoluteString)")
            _ = await ingestURLAdvanced(url, modeLabel: "standard", sameDomainDepth: 1)
            snippetDetails = await retrieveMemorySnippetDetails(matching: text, limit: 8)
        }
        if let h = host { await ensureHostMemoryArtifacts(host: h) }
        var evidenceLines: [String] = []
        if let h = host {
            let evidence = await fetchCitedEvidence(host: h, depthLevel: config.depthLevel)
            evidenceLines = evidence.map { "• " + trim($0.text, limit: 280) + " — [" + trim($0.title, limit: 80) + "](\($0.url))" }
            await MainActor.run {
                self.recentEvidence = evidence.enumerated().map { idx, e in
                    CitedSegmentEvidence(id: "ev-\(idx)", title: e.title, url: e.url, text: self.trim(e.text, limit: 400))
                }
            }
        } else if !snippetDetails.isEmpty {
            for d in snippetDetails {
                if let pid = d.pageId, let meta = await fetchPageMeta(pageId: pid) {
                    evidenceLines.append("• \(d.text) — [\(meta.title)](\(meta.url))")
                } else {
                    evidenceLines.append("• \(d.text)")
                }
            }
        }

        let baselines = await retrieveRecentBaselines(limit: 6)
        let drifts = await retrieveRecentDrifts(limit: 3)
        let patterns = await retrieveRecentPatterns(limit: 2)
        logTrail("deep-mode: facts baselines=\(baselines.count) drift=\(drifts.count) patterns=\(patterns.count) evidence=\(evidenceLines.count)")
        let baselinesBlock = await condenseList(header: "Baselines", items: baselines, budget: 1400)
        let driftBlock = await condenseList(header: "Recent Drift", items: drifts, budget: 1000)
        let patternsBlock = await condenseList(header: "Patterns", items: patterns, budget: 1000)

        // Build FactPack
        var factPack: [String] = []
        if let h = host, !h.isEmpty {
            factPack.append("Subject: \(h)")
        }
        if !evidenceLines.isEmpty {
            factPack.append("Evidence:\n" + evidenceLines.joined(separator: "\n"))
        }
        if !baselines.isEmpty { factPack.append(baselinesBlock) }
        if !drifts.isEmpty { factPack.append(driftBlock) }
        if !patterns.isEmpty { factPack.append(patternsBlock) }

        // Enforce strict composition rules to avoid superficial answers
        var instructions = [
            "Compose strictly from the FactPack. Do not invent.",
            "Prefer specificity and include citations in bullets as [Title](URL) when available.",
            "If a requested fact is not present, state: 'Not in memory' and suggest refinement.",
        ]
        if host != nil {
            instructions.append("Title your answer: 'As of our stored snapshot'.")
            instructions.append("Write 3–5 sections; each with 2–4 bullets.")
        } else {
            instructions.append("Write 6–9 concise bullets.")
        }

        let sys = vm.makeSystemPrompts(base: policy + [
            "AnsweringPolicy:\n- " + instructions.joined(separator: "\n- "),
            "FactPack:\n" + factPack.joined(separator: "\n\n")
        ])

        // Track injected context for inspector
        let ctx = InjectedContext(
            continuity: continuityDigest,
            awarenessSummary: vm.awarenessSummaryText,
            awarenessHistory: vm.awarenessHistorySummary,
            snippets: snippetDetails.map { $0.text },
            baselines: baselines,
            drifts: drifts,
            patterns: patterns
        )
        lastInjectedContext = ctx
        pendingContext = ctx

        if config.showSemanticPanel {
            let panel = await buildSemanticPanel(from: snippetDetails, baselines: baselines, patterns: patterns)
            await MainActor.run { self.semanticPanel = panel }
        }

        await MainActor.run {
            self.vm.send(prompt: text, systemPrompts: sys, preferStreaming: true, corpusOverride: nil)
        }
    }

    // Extract a URL or domain from a prompt. Supports raw domains like example.com
    private func _extractURLOrDomain(from prompt: String) -> URL? {
        let s = prompt
        // 1) Try explicit http(s) URLs
        if let m = s.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
            return URL(string: String(s[m]))
        }
        // 2) Try bare domain pattern (example.com or sub.example.co.uk)
        if let m = s.range(of: #"\b([A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b"#, options: .regularExpression) {
            let dom = String(s[m])
            if dom.lowercased().hasPrefix("http") { return URL(string: dom) }
            return URL(string: "https://\(dom)")
        }
        return nil
    }

    private static func _baselineIntent(in s: String) -> Bool {
        let q = s.lowercased()
        if q.contains("baseline") { return true }
        if q.contains("what do we know") { return true }
        if q.contains("what are our baselines") { return true }
        return false
    }

    private func trim(_ s: String, limit: Int = 600) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        return String(t.prefix(limit - 1)) + "…"
    }

    // MARK: - Semantic titles
    public func generateCorpusTitle() async {
        do {
            let (bCount, _) = try await store.listBaselines(corpusId: config.memoryCorpusId, limit: 3, offset: 0)
            let (rCount, _) = try await store.listReflections(corpusId: config.memoryCorpusId, limit: 5, offset: 0)
            let (sCount, segs) = try await store.listSegments(corpusId: config.memoryCorpusId, limit: 5, offset: 0)
            let sample = segs.prefix(3).map { "• \($0.text)" }.joined(separator: "\n")
            let prompt = """
            Create a 3–7 word human-readable title for a knowledge corpus.
            Use neutral language; no punctuation at the end. Prefer nouns.
            You are given quick stats and up to three sample snippets.

            Stats: baselines=\(bCount), reflections=\(rCount), segments=\(sCount)
            Snippets:\n\(sample)
            """
            if let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                               openAIEndpoint: config.openAIEndpoint,
                                                               localEndpoint: nil) {
                let client = OpenAICompatibleChatProvider(apiKey: selection.usesAPIKey ? config.openAIAPIKey : nil,
                                                          endpoint: selection.endpoint)
                let req = CoreChatRequest(model: config.model, messages: [
                    .init(role: .system, content: "You write short, crisp titles."),
                    .init(role: .user, content: prompt)
                ])
                if let title = try? await client.complete(request: req).answer.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    await MainActor.run { self.corpusTitle = String(title.prefix(72)) }
                    return
                }
            }
        } catch { /* ignore */ }
        await MainActor.run { self.corpusTitle = nil }
    }

    private func suggestChatTitle(from turn: EngraverChatTurn) async {
        guard chatTitle == nil || chatTitle?.isEmpty == true else { return }
        if let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                           openAIEndpoint: config.openAIEndpoint,
                                                           localEndpoint: nil) {
            let client = OpenAICompatibleChatProvider(apiKey: selection.usesAPIKey ? config.openAIAPIKey : nil,
                                                      endpoint: selection.endpoint)
            let prompt = """
            Create a 3–7 word title for a chat based on the user's message and assistant's reply. Neutral, descriptive, no ending punctuation.
            User: \(turn.prompt)\nAssistant: \(turn.answer)
            """
            let req = CoreChatRequest(model: config.model, messages: [
                .init(role: .system, content: "You write short, crisp titles."),
                .init(role: .user, content: prompt)
            ])
            if let title = try? await client.complete(request: req).answer.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                await MainActor.run { self.chatTitle = String(title.prefix(72)) }
            }
        }
    }

    private func latestContinuityPageId() async throws -> String? {
        // Fallback to simple filters-only query and compute prefix match client-side
        let q = Query(filters: ["corpusId": config.memoryCorpusId], limit: 1000, offset: 0)
        let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
        struct PageDoc: Codable { let pageId: String }
        let pages: [PageDoc] = resp.documents.compactMap { try? JSONDecoder().decode(PageDoc.self, from: $0) }
        let continuity = pages.map { $0.pageId }.filter { $0.hasPrefix("continuity:") }.sorted(by: >)
        return continuity.first
    }

    private func loadContinuityDigest() async {
        do {
            guard let pageId = try await latestContinuityPageId() else { return }
            let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": pageId], limit: 5, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
            // Use the first segment's text as digest (trimmed)
            struct SegmentDoc: Codable { let text: String }
            if let data = resp.documents.first, let seg = try? JSONDecoder().decode(SegmentDoc.self, from: data) {
                await MainActor.run { self.continuityDigest = trim(seg.text, limit: 600) }
            }
        } catch {
            // ignore
        }
    }

    // MARK: - Memory retrieval
    private struct SegmentDocDetail: Codable { let text: String; let pageId: String?; let entities: [String]? }

    private struct SemanticSnippet: Sendable, Equatable { let text: String; let pageId: String?; let entities: [String] }

    private func retrieveMemorySnippetDetails(matching query: String, limit: Int = 5) async -> [SemanticSnippet] {
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let needle = trimmed.split(separator: " ").prefix(8).joined(separator: " ")
            var q = Query(filters: ["corpusId": config.memoryCorpusId], limit: limit * 3, offset: 0)
            if !needle.isEmpty { q.text = String(needle) }
            q.sort = [("updatedAt", false)]
            let start = Date()
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
            let details: [SemanticSnippet] = resp.documents.compactMap { data in
                guard let d = try? JSONDecoder().decode(SegmentDocDetail.self, from: data) else { return nil }
                return SemanticSnippet(text: trim(d.text, limit: 320), pageId: d.pageId, entities: d.entities ?? [])
            }
            let unique = Array(details.prefix(limit))
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            logTrail("STORE /segments ok in \(ms) ms (n=\(unique.count))")
            return unique
        } catch {
            logTrail("store.segments error • \(error)")
            return []
        }
    }
    private func retrieveMemorySnippets(matching query: String, limit: Int = 5) async -> [String] {
        // Store-only retrieval for memory snippets (no Semantic Browser dependency at runtime).
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let needle = trimmed.split(separator: " ").prefix(8).joined(separator: " ")
            var q = Query(filters: ["corpusId": config.memoryCorpusId], limit: limit * 3, offset: 0)
            if !needle.isEmpty { q.text = String(needle) }
            // Prefer most recently updated segments if available
            q.sort = [("updatedAt", false)]
            let start = Date()
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
            struct SegmentDoc: Codable { let text: String }
            let texts: [String] = resp.documents.compactMap { data in
                (try? JSONDecoder().decode(SegmentDoc.self, from: data))?.text
            }
            let unique = Array(Set(texts)).prefix(limit)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            logTrail("STORE /segments ok in \(ms) ms (n=\(unique.count))")
            return unique.map { trim($0, limit: 320) }
        } catch {
            logTrail("store.segments error • \(error)")
            return []
        }
    }

    private func retrieveRecentBaselines(limit: Int = 3) async -> [String] {
        do {
            let (total, items) = try await store.listBaselines(corpusId: config.memoryCorpusId, limit: 1000, offset: 0)
            let sorted = items.sorted { $0.ts > $1.ts }
            let picked = Array(sorted.prefix(limit)).map { trim($0.content, limit: 360) }
            logTrail("STORE /baselines ok (n=\(total), used=\(picked.count))")
            return picked
        } catch {
            logTrail("store.baselines error • \(error)")
            return []
        }
    }

    private func retrieveRecentDrifts(limit: Int = 3) async -> [String] {
        do {
            let (total, items) = try await store.listDrifts(corpusId: config.memoryCorpusId, limit: 1000, offset: 0)
            let sorted = items.sorted { $0.ts > $1.ts }
            let picked = Array(sorted.prefix(limit)).map { trim($0.content, limit: 480) }
            logTrail("STORE /drifts ok (n=\(total), used=\(picked.count))")
            return picked
        } catch { logTrail("store.drifts error • \(error)"); return [] }
    }

    private func retrieveRecentPatterns(limit: Int = 2) async -> [String] {
        do {
            let (total, items) = try await store.listPatterns(corpusId: config.memoryCorpusId, limit: 1000, offset: 0)
            let sorted = items.sorted { $0.ts > $1.ts }
            let picked = Array(sorted.prefix(limit)).map { trim($0.content, limit: 640) }
            logTrail("STORE /patterns ok (n=\(total), used=\(picked.count))")
            return picked
        } catch { logTrail("store.patterns error • \(error)"); return [] }
    }

    // MARK: - Semantic Panel builder
    private func buildSemanticPanel(from snippets: [SemanticSnippet], baselines: [String], patterns: [String]) async -> SemanticPanel? {
        var entityCounts: [String: Int] = [:]
        for s in snippets { for e in s.entities { entityCounts[e, default: 0] += 1 } }
        let topicName = entityCounts.max(by: { $0.value < $1.value })?.key
        let topicType: String? = nil

        let pageIds = Array(Set(snippets.compactMap { $0.pageId })).prefix(5)
        var sources: [SemanticPanel.Source] = []
        for pid in pageIds {
            if let title = await fetchPageTitle(pageId: pid) {
                sources.append(.init(id: pid, title: title))
            } else {
                sources.append(.init(id: pid, title: pid))
            }
        }

        let stepstones: [String]
        if !patterns.isEmpty { stepstones = patterns }
        else if !baselines.isEmpty { stepstones = baselines }
        else { stepstones = [] }

        if topicName == nil && sources.isEmpty && stepstones.isEmpty { return nil }
        return SemanticPanel(topicName: topicName, topicType: topicType, sources: sources, stepstones: stepstones)
    }

    private func fetchPageTitle(pageId: String) async -> String? {
        do {
            let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": pageId], limit: 1, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
            struct PageDoc: Codable { let title: String }
            if let first = resp.documents.first, let doc = try? JSONDecoder().decode(PageDoc.self, from: first) { return doc.title }
            return nil
        } catch { return nil }
    }

    private func fetchPageMeta(pageId: String) async -> (title: String, url: String)? {
        do {
            let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": pageId], limit: 1, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
            struct PageDoc: Codable { let title: String; let url: String }
            if let first = resp.documents.first, let doc = try? JSONDecoder().decode(PageDoc.self, from: first) { return (doc.title, doc.url) }
            return nil
        } catch { return nil }
    }

    private func fetchHostCoverage(host: String, limit: Int = 8) async -> (pages: Int, segments: Int, recent: [(title: String, url: String)]) {
        do {
            var qp = Query(filters: ["corpusId": config.memoryCorpusId, "host": host], limit: limit, offset: 0)
            qp.sort = [("fetchedAt", false)]
            let pagesResp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: qp)
            struct PageDoc: Codable { let pageId: String; let title: String; let url: String }
            let pageDocs = pagesResp.documents.compactMap { try? JSONDecoder().decode(PageDoc.self, from: $0) }
            let recent = pageDocs.map { (title: $0.title, url: $0.url) }
            var segCount = 0
            for p in pageDocs {
                let sq = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": p.pageId], limit: 1, offset: 0)
                if let r = try? await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: sq) { segCount += r.total }
            }
            return (pages: pagesResp.total, segments: segCount, recent: recent)
        } catch { return (0,0,[]) }
    }

    // Fetch recent textual segments for a host (for strict memory mode fallback)
    private func fetchRecentCitedSegments(host: String, limit: Int = 8) async -> [(text: String, title: String, url: String)] {
        do {
            // List recent pages for host, then take first segments per page
            var qp = Query(filters: ["corpusId": config.memoryCorpusId, "host": host], limit: max(limit, 12), offset: 0)
            qp.sort = [("fetchedAt", false)]
            let pageResp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: qp)
            struct PageDoc: Codable { let pageId: String; let title: String; let url: String }
            let pages = pageResp.documents.compactMap { try? JSONDecoder().decode(PageDoc.self, from: $0) }
            var out: [(String,String,String)] = []
            for p in pages {
                let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": p.pageId], limit: 2, offset: 0)
                if let segResp = try? await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q) {
                    struct Seg: Codable { let text: String }
                    for d in segResp.documents {
                        if let s = try? JSONDecoder().decode(Seg.self, from: d) {
                            out.append((s.text, p.title, p.url))
                            if out.count >= limit { return out }
                        }
                    }
                }
            }
            return out
        } catch { return [] }
    }

    // Condense list to within a rough character budget. If material exceeds the
    // budget and a provider is configured, ask the model to compress into
    // information-preserving bullets. Falls back to simple bullets if needed.
    private func condenseList(header: String, items: [String], budget: Int) async -> String {
        let bullets = items.map { "• \($0)" }.joined(separator: "\n")
        let raw = "\(header):\n\(bullets)"
        if raw.count <= budget { return raw }
        if let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                           openAIEndpoint: config.openAIEndpoint,
                                                           localEndpoint: nil) {
            let client = OpenAICompatibleChatProvider(apiKey: selection.usesAPIKey ? config.openAIAPIKey : nil,
                                                      endpoint: selection.endpoint)
            let system = "You compress notes into crisp bullet points while preserving key information, names, numbers, and chronology. Avoid hedging."
            let prompt = "Summarize the following \(header.lowercased()) into 5–9 bullets preserving information value.\n\n\(bullets)"
            let req = CoreChatRequest(model: config.model, messages: [
                .init(role: .system, content: system),
                .init(role: .user, content: prompt)
            ])
            if let answer = try? await client.complete(request: req).answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let compact = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(header):\n\(compact)"
            }
        }
        // Fallback: return original bullets (they may be truncated downstream by the model context window)
        return raw
    }

    // MARK: - Post-index segmentation (quality pass)
    /// Re-segment thin/label-like pages into 2–5 paragraph segments per page.
    /// Returns number of pages re-segmented.
    public func resegmentThinPages(host: String? = nil, maxPages: Int = 50) async -> Int {
        do {
            var filters: [String: String] = ["corpusId": config.memoryCorpusId]
            if let host, !host.isEmpty { filters["host"] = host }
            var qp = Query(filters: filters, limit: maxPages, offset: 0)
            qp.sort = [("fetchedAt", false)]
            let pagesResp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: qp)
            struct PageDoc: Codable { let pageId: String; let url: String }
            let pages = pagesResp.documents.compactMap { try? JSONDecoder().decode(PageDoc.self, from: $0) }
            var changed = 0
            for p in pages {
                let segQ = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": p.pageId], limit: 200, offset: 0)
                let segResp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: segQ)
                struct RawSeg: Codable { let id: String?; let segmentId: String?; let text: String }
                let segs = segResp.documents.compactMap { try? JSONDecoder().decode(RawSeg.self, from: $0) }
                let count = segResp.total
                let avgLen = max(1, segs.map { $0.text.count }.reduce(0, +) / max(1, segs.count))
                let looksThin = (count == 0) || (avgLen < 90)
                guard looksThin else { continue }
                // Construct source text: fetch if none, else join
                var sourceText: String = segs.isEmpty ? "" : segs.map { $0.text }.joined(separator: "\n\n")
                if sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let u = URL(string: p.url) {
                        var req = URLRequest(url: u); req.httpMethod = "GET"; req.timeoutInterval = 10
                        if let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                            let html = String(data: data, encoding: .utf8) ?? ""
                            sourceText = Self._stripHTML(html)
                        }
                    }
                }
                let chunks = Self._chunkText(sourceText, maxSegments: 5, targetChars: 360)
                guard !chunks.isEmpty else { continue }
                // Delete existing segments for page (best-effort)
                for s in segs {
                    let docId = s.segmentId ?? s.id
                    if let docId {
                        try? await store.deleteDoc(corpusId: config.memoryCorpusId, collection: "segments", id: docId)
                    }
                }
                // Insert new segments
                for (i, text) in chunks.enumerated() {
                    let segId = "\(p.pageId):\(i)"
                    let seg = Segment(corpusId: config.memoryCorpusId, segmentId: segId, pageId: p.pageId, kind: "paragraph", text: text)
                    _ = try? await store.addSegment(seg)
                }
                changed += 1
            }
            if changed > 0 { logTrail("post-index segmentation updated pages=\(changed)") }
            return changed
        } catch {
            logTrail("post-index segmentation error • \(error)")
            return 0
        }
    }

    // MARK: - Evidence and Baseline/Drift/Patterns/Reflection calculus

    // Scale evidence size based on a 1..3 depth level
    private func fetchCitedEvidence(host: String, depthLevel: Int) async -> [(text: String, title: String, url: String)] {
        let level = max(1, min(depthLevel, 3))
        let limits: [Int] = [8, 16, 32]
        let limit = limits[level - 1]
        return await fetchRecentCitedSegments(host: host, limit: limit)
    }

    // Compose a baseline from cited evidence; prefer LLM, fallback to deterministic bullets.
    private func composeBaseline(from evidence: [(text: String, title: String, url: String)], host: String, deep: Bool) async -> String {
        guard !evidence.isEmpty else { return "" }
        if let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                          openAIEndpoint: config.openAIEndpoint,
                                                          localEndpoint: nil) {
            let client = OpenAICompatibleChatProvider(apiKey: selection.usesAPIKey ? config.openAIAPIKey : nil,
                                                      endpoint: selection.endpoint)
            let header = deep ? "Create a Deep Baseline for \(host)" : "Create a Baseline for \(host)"
            let system = "You write concise, factual bullets from provided paragraph evidence. Each bullet is a complete sentence and MUST end with a citation [Title](URL). No hedging or generic language."
            let packet = evidence.map { "• \(trim($0.text, limit: 400)) — [\(trim($0.title, limit: 120))](\($0.url))" }.joined(separator: "\n")
            let ask = """
            \(header).
            Requirements:
            - 6–9 bullets (if deep: up to 12)
            - Cover what it is, who it’s for, what it offers, how it works, pricing/plans if present, proof (customers/case studies) if present
            - Every bullet MUST end with a citation [Title](URL) from the evidence
            Evidence:\n\(packet)
            """
            let req = CoreChatRequest(model: config.model, messages: [
                .init(role: .system, content: system),
                .init(role: .user, content: ask)
            ])
            if let answer = try? await client.complete(request: req).answer.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty {
                return answer
            }
        }
        // Deterministic fallback: pick first N evidence items by diversity of titles
        var seen: Set<String> = []
        var bullets: [String] = []
        for e in evidence {
            let key = e.title.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            let sentence = trim(e.text, limit: 260)
            bullets.append("• \(sentence) [\(trim(e.title, limit: 80))](\(e.url))")
            if bullets.count >= (deep ? 12 : 9) { break }
        }
        return bullets.joined(separator: "\n")
    }

    // Compute a typed drift between two baselines deterministically; uses simple token alignment
    private func computeTypedDriftDeterministic(new: String, old: String) -> String {
        func splitBullets(_ s: String) -> [String] {
            s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        func norm(_ s: String) -> Set<String> {
            let lowered = s.lowercased()
            let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            let tokens = cleaned.split(separator: " ").map(String.init).filter { $0.count > 2 }
            return Set(tokens)
        }
        let newB = splitBullets(new)
        let oldB = splitBullets(old)
        var usedOld = Set<Int>()
        var added: [String] = []
        var changed: [String] = []
        var removed: [String] = []
        // Match new to old
        for nb in newB {
            let nset = norm(nb)
            var bestIdx: Int? = nil
            var bestScore = 0
            for (i, ob) in oldB.enumerated() where !usedOld.contains(i) {
                let oset = norm(ob)
                let score = nset.intersection(oset).count
                if score > bestScore { bestScore = score; bestIdx = i }
            }
            if let idx = bestIdx, bestScore > 2 {
                usedOld.insert(idx)
                let ob = oldB[idx]
                if nb != ob {
                    changed.append("Changed: \(nb)")
                }
            } else {
                added.append("Added: \(nb)")
            }
        }
        for (i, ob) in oldB.enumerated() where !usedOld.contains(i) {
            removed.append("Removed: \(ob)")
        }
        let header = "Drift since last baseline: \(added.count) added, \(changed.count) changed, \(removed.count) removed."
        return ([header] + added + changed + removed).joined(separator: "\n")
    }

    private func computePatternsDeterministic(from baseline: String, and drift: String) -> [String] {
        func tokenize(_ s: String) -> [String] {
            s.lowercased().replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
                .split(separator: " ").map(String.init).filter { $0.count > 3 && !$0.allSatisfy({ $0.isNumber }) }
        }
        let claims = baseline.split(separator: "\n").map(String.init) + drift.split(separator: "\n").map(String.init)
        var freq: [String: Int] = [:]
        for c in claims { for t in Set(tokenize(c)) { freq[t, default: 0] += 1 } }
        let common = freq.sorted { $0.value > $1.value }.prefix(6)
        return common.map { "Recurring: '\($0.key)' appears across \($0.value) claims." }
    }

    private func composeReflectionDeterministic(drift: String, patterns: [String], label: String?) -> String {
        let header: String
        if let label, !label.isEmpty { header = "Reflection: \(label)" } else { header = "Reflection" }
        let counts: (Int, Int, Int) = {
            var add = 0, chg = 0, rem = 0
            for line in drift.split(separator: "\n") {
                let l = line.lowercased()
                if l.hasPrefix("added:") { add += 1 }
                if l.hasPrefix("changed:") { chg += 1 }
                if l.hasPrefix("removed:") { rem += 1 }
            }
            return (add, chg, rem)
        }()
        var out: [String] = []
        out.append("\(header): Drift summary — added=\(counts.0), changed=\(counts.1), removed=\(counts.2).")
        if !patterns.isEmpty {
            let tops = patterns.prefix(3).joined(separator: "; ")
            out.append("Observed patterns: \(tops).")
        }
        if let first = drift.split(separator: "\n").first, first.lowercased().contains("drift since") {
            out.insert(String(first), at: 1)
        }
        return out.prefix(7).joined(separator: "\n")
    }

    // Ensure we have at least one baseline and recent artifacts; throttle per host
    private func ensureHostMemoryArtifacts(host: String) async {
        let now = Date()
        if let last = lastArtifactsByHost[host], now.timeIntervalSince(last) < 120 { return }
        defer { lastArtifactsByHost[host] = now }
        do {
            // Count baselines
            let (bTotal, _) = try await store.listBaselines(corpusId: config.memoryCorpusId, limit: 2, offset: 0)
            if bTotal == 0 {
                let ev = await fetchCitedEvidence(host: host, depthLevel: 1)
                let baseline = await composeBaseline(from: ev, host: host, deep: false)
                if !baseline.isEmpty {
                    await persistBaseline(content: baseline)
                    lastBaselineText = baseline
                }
            }
        } catch { /* ignore */ }
    }

    // Persist helpers (Awareness → Store fallback)
    private func persistBaseline(content: String) async {
        if let base = config.awarenessURL {
            do {
                let client = AwarenessClient(baseURL: base)
                let req = Components.Schemas.BaselineRequest(corpusId: config.memoryCorpusId,
                                                             baselineId: "baseline-\(Int(Date().timeIntervalSince1970))",
                                                             content: content)
                _ = try await client.addBaseline(req)
                logTrail("POST /corpus/baseline 200")
            } catch { logTrail("POST /corpus/baseline error • \(error)") }
        }
        do {
            let rec = Baseline(corpusId: config.memoryCorpusId, baselineId: "baseline-\(Int(Date().timeIntervalSince1970))", content: content)
            _ = try await store.addBaseline(rec)
            logTrail("STORE /baselines ok")
        } catch { logTrail("STORE /baselines error • \(error)") }
    }

    private func persistDrift(content: String) async {
        if let base = config.awarenessURL { await postDrift(to: base, content: content) }
        else { do { _ = try await store.addDrift(Drift(corpusId: config.memoryCorpusId, driftId: "drift-\(Int(Date().timeIntervalSince1970))", content: content)); logTrail("STORE /drifts ok") } catch { logTrail("STORE /drifts error • \(error)") } }
    }

    private func persistPatterns(content: String) async {
        if let base = config.awarenessURL { await postPatterns(to: base, content: content) }
        else { do { _ = try await store.addPatterns(Patterns(corpusId: config.memoryCorpusId, patternsId: "patterns-\(Int(Date().timeIntervalSince1970))", content: content)); logTrail("STORE /patterns ok") } catch { logTrail("STORE /patterns error • \(error)") } }
    }

    private func persistReflection(content: String) async {
        if let base = config.awarenessURL {
            do {
                let client = AwarenessClient(baseURL: base)
                let req = Components.Schemas.ReflectionRequest(corpusId: config.memoryCorpusId,
                                                              reflectionId: "reflection-\(Int(Date().timeIntervalSince1970))",
                                                              question: "tracking-cycle",
                                                              content: content)
                _ = try await client.addReflection(req)
                logTrail("POST /corpus/reflections 200")
            } catch { logTrail("POST /corpus/reflections error • \(error)") }
        } else {
            do { _ = try await store.addReflection(Reflection(corpusId: config.memoryCorpusId, reflectionId: "reflection-\(Int(Date().timeIntervalSince1970))", question: "tracking-cycle", content: content)); logTrail("STORE /reflections ok") } catch { logTrail("STORE /reflections error • \(error)") }
        }
    }

    /// Public entry: build baseline at given level (1..3), then compute drift/patterns/reflection and persist all.
    public func buildBaselineAndArtifacts(for host: String, level: Int = 3) async -> Bool {
        let depth = max(1, min(level, 3))
        let evidence = await fetchCitedEvidence(host: host, depthLevel: depth)
        guard !evidence.isEmpty else { logTrail("baseline: no evidence for host=\(host)"); return false }
        // Deterministic baseline from evidence (bare, neutral). No implications.
        let baseline = composeBaselineDeterministic(from: evidence)
        guard !baseline.isEmpty else { logTrail("baseline: compose returned empty") ; return false }
        // Persist baseline
        await persistBaseline(content: baseline)
        // Compute drift against last baseline if present
        var driftText: String = ""
        if let prev = lastBaselineText, !prev.isEmpty {
            driftText = computeTypedDriftDeterministic(new: baseline, old: prev)
            await persistDrift(content: driftText)
        }
        lastBaselineText = baseline
        // Patterns
        let patternsList = computePatternsDeterministic(from: baseline, and: driftText)
        let patterns = patternsList.joined(separator: "\n")
        if !patterns.isEmpty { await persistPatterns(content: patterns) }
        // Reflection
        let reflection = composeReflectionDeterministic(drift: driftText, patterns: patternsList, label: host)
        if !reflection.isEmpty { await persistReflection(content: reflection) }
        await MainActor.run {
            self.calculusReport = GenerationReport(baselineSource: .deterministic,
                                                   driftSource: .deterministic,
                                                   patternsSource: .deterministic,
                                                   reflectionSource: .deterministic,
                                                   evidenceCount: evidence.count,
                                                   baselineLength: baseline.count,
                                                   driftLines: driftText.split(separator: "\n").count,
                                                   patternsLines: patternsList.count)
        }
        logTrail("baseline cycle complete • host=\(host) level=\(level)")
        return true
    }

    /// Accepts a user-supplied baseline text, computes deterministic Drift/Patterns/Reflection, and persists all.
    public func submitBaselineFromUser(_ content: String, label: String? = nil) async -> Bool {
        let baseline = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseline.isEmpty else { return false }
        await persistBaseline(content: baseline)
        var driftText = ""
        if let prev = lastBaselineText, !prev.isEmpty { driftText = computeTypedDriftDeterministic(new: baseline, old: prev); await persistDrift(content: driftText) }
        lastBaselineText = baseline
        let patternsList = computePatternsDeterministic(from: baseline, and: driftText)
        let patterns = patternsList.joined(separator: "\n")
        if !patterns.isEmpty { await persistPatterns(content: patterns) }
        let reflection = composeReflectionDeterministic(drift: driftText, patterns: patternsList, label: label)
        if !reflection.isEmpty { await persistReflection(content: reflection) }
        await MainActor.run {
            self.calculusReport = GenerationReport(baselineSource: .user,
                                                   driftSource: .deterministic,
                                                   patternsSource: .deterministic,
                                                   reflectionSource: .deterministic,
                                                   evidenceCount: 0,
                                                   baselineLength: baseline.count,
                                                   driftLines: driftText.split(separator: "\n").count,
                                                   patternsLines: patternsList.count)
        }
        return true
    }

    private func composeBaselineDeterministic(from evidence: [(text: String, title: String, url: String)]) -> String {
        var seen: Set<String> = []
        var bullets: [String] = []
        for e in evidence {
            let key = e.title.lowercased()
            if !seen.insert(key).inserted { continue }
            bullets.append("• " + trim(e.text, limit: 260) + " [" + trim(e.title, limit: 80) + "](\(e.url))")
            if bullets.count >= 9 { break }
        }
        return bullets.joined(separator: "\n")
    }

    private func ensureAwarenessContext(timeoutMs: Int = 1800) async {
        await MainActor.run { vm.refreshAwareness() }
        let start = Date()
        while vm.awarenessStatus.isRefreshing {
            if Int(Date().timeIntervalSince(start) * 1000) > timeoutMs { break }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    // MARK: - Synthesis using provider
    private func synthesizeBaselineText(_ ctx: InjectedContext) async -> String? {
        let provider = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                       openAIEndpoint: config.openAIEndpoint,
                                                       localEndpoint: nil)
        guard let selection = provider else { return nil }
        let client = OpenAICompatibleChatProvider(apiKey: provider?.usesAPIKey == true ? config.openAIAPIKey : nil,
                                                  endpoint: selection.endpoint)
        let summary = ctx.awarenessSummary ?? ""
        let history = ctx.awarenessHistory ?? ""
        let snippetsText = ctx.snippets.isEmpty ? "(none)" : ctx.snippets.joined(separator: "\n• ")
        let materials = "Summary:\n\(summary)\n\nHistory:\n\(history)\n\nSnippets:\n• \(snippetsText)"
        let system = "You are the Baseline Synthesizer. Produce a concise corpus baseline (3–6 bullets) that captures enduring facts/themes. No speculation."
        let req = CoreChatRequest(model: config.model, messages: [
            CoreChatMessage(role: .system, content: system),
            CoreChatMessage(role: .user, content: materials)
        ])
        do {
            let resp = try await client.complete(request: req)
            return resp.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logTrail("POST /openai/chat error • \(error)")
            return nil
        }
    }

    // MARK: - Test helpers (internal)
    func _testContinuityDigest() -> String? { continuityDigest }

    private static func makeChatCorpusId() -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(6)
        return "chat-\(ts)-\(suffix)"
    }

    // MARK: - Awareness integration & reflections
    private func logTrail(_ event: String) {
        let stamp = Int(Date().timeIntervalSince1970) % 100000
        let line = "[\(stamp)] \(event)"
        if memoryTrail.count > 80 { memoryTrail.removeFirst(memoryTrail.count - 80) }
        memoryTrail.append(line)
    }

    private func refreshAwareness(reason: String) async {
        logTrail("awareness.refresh (reason=\(reason))")
        await MainActor.run { vm.refreshAwareness() }
    }

    // MARK: - Ingestion (Semantic Browser / Files)
    public func learnSite(url: URL, modeLabel: String = "standard", depth: Int = 2, maxPages: Int = 12) async -> Bool {
        guard let browser = browserConfig else { return false }
        let mode: SeedingConfiguration.Browser.Mode = {
            switch modeLabel.lowercased() { case "deep": return .deep; case "quick": return .quick; default: return .standard }
        }()
        let opts = LearnSiteCrawler.Options(mode: mode, pagesLimit: maxPages, maxDepth: depth, sameHostOnly: true)
        let crawler = LearnSiteCrawler()
        let t0 = Date()
        do {
            await MainActor.run { self.learnProgress = LearnProgress(visited: 0, pages: 0, segs: 0, target: maxPages) }
            let cov = try await crawler.learn(seed: url, semanticBrowserURL: browser.baseURL, corpusId: config.memoryCorpusId, options: opts, log: { msg in
                Task { @MainActor in self.logTrail(msg) }
            }, progress: { v, p, s in
                Task { @MainActor in self.learnProgress = LearnProgress(visited: v, pages: p, segs: s, target: maxPages) }
            })
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            await MainActor.run { self.logTrail("learn complete • visited=\(cov.visited) pages=\(cov.pagesIndexed) segs=\(cov.segmentsIndexed) • \(ms) ms") }
            let ok = cov.pagesIndexed > 0 || cov.segmentsIndexed > 0
            // Run a quick post-index segmentation pass if segments are low
            if cov.pagesIndexed > 0 && cov.segmentsIndexed == 0 {
                _ = await self.resegmentThinPages(host: url.host, maxPages: maxPages)
            }
            // Update recent evidence for the learned host
            if let h = url.host {
                let ev = await self.fetchRecentCitedSegments(host: h, limit: 8)
                await MainActor.run {
                    self.recentEvidence = ev.enumerated().map { idx, e in CitedSegmentEvidence(id: "ev-\(idx)", title: e.title, url: e.url, text: self.trim(e.text, limit: 400)) }
                }
            }
            await MainActor.run { self.learnProgress = nil }
            return ok
        } catch {
            await MainActor.run { self.logTrail("learn error • \(error)") }
            await MainActor.run { self.learnProgress = nil }
            return false
        }
    }

    public func ingestURL(_ url: URL, labels: [String] = []) async -> Bool {
        guard let browser = browserConfig else { return false }
        let source = SeedingConfiguration.Source(name: url.host ?? url.absoluteString,
                                                 url: url,
                                                 corpusId: config.memoryCorpusId,
                                                 labels: labels)
        let seeder = SemanticBrowserSeeder()
        do {
            let metrics = try await seeder.run(source: source, browser: browser) { msg in
                Task { @MainActor in self.logTrail(msg) }
            }
            await MainActor.run { self.logTrail("semantic-browser indexed • \(metrics.pagesUpserted) segs=\(metrics.segmentsUpserted)") }
            // Verify the newly indexed content is visible in our memory corpus. If not, fallback to direct import.
            if await _verifyIndexed(host: url.host) { return true }
            await MainActor.run { self.logTrail("semantic-browser verify • no pages for host; attempting direct import") }
            if await _fallbackFetchAndImport(url: url) {
                await MainActor.run { self.logTrail("direct import ok • host=\(url.host ?? "?")") }
                return true
            }
            await MainActor.run { self.logTrail("direct import failed • host=\(url.host ?? "?")") }
            return false
        } catch {
            await MainActor.run { self.logTrail("semantic-browser error • \(error)") }
            // Fallback: try direct fetch/import when the browser is unavailable
            if await _fallbackFetchAndImport(url: url) {
                await MainActor.run { self.logTrail("direct import ok • host=\(url.host ?? "?")") }
                return true
            }
            return false
        }
    }

    /// Advanced ingestion allowing caller to request a deeper analysis mode and a small same-domain crawl.
    public func ingestURLAdvanced(_ url: URL, modeLabel: String? = nil, sameDomainDepth: Int = 0) async -> Bool {
        let chosen: SeedingConfiguration.Browser.Mode? = {
            switch (modeLabel ?? "").lowercased() {
            case "quick": return .quick
            case "deep": return .deep
            case "standard": return .standard
            default: return nil
            }
        }()
        // Start with the single page using chosen mode if provided
        var ok = await _ingestSingle(url, overrideMode: chosen)
        if !ok {
            // Single-page ingest failed; already attempted direct import inside.
            return false
        }
        // Optionally follow a few same-domain links
        if sameDomainDepth > 0, let host = url.host, await _verifyIndexed(host: host) {
            ok = await ingestSameHostLinks(seed: url, count: sameDomainDepth, mode: chosen ?? .standard) > 0 || ok
        }
        if ok, let host = url.host {
            _ = await self.resegmentThinPages(host: host, maxPages: 24)
        }
        return ok
    }

    private func _ingestSingle(_ url: URL, overrideMode: SeedingConfiguration.Browser.Mode?) async -> Bool {
        guard let baseBrowser = browserConfig else { return false }
        let browser: SeedingConfiguration.Browser = {
            if let m = overrideMode {
                return SeedingConfiguration.Browser(
                    baseURL: baseBrowser.baseURL,
                    apiKey: baseBrowser.apiKey,
                    mode: m,
                    defaultLabels: baseBrowser.defaultLabels,
                    pagesCollection: baseBrowser.pagesCollection,
                    segmentsCollection: baseBrowser.segmentsCollection,
                    entitiesCollection: baseBrowser.entitiesCollection,
                    tablesCollection: baseBrowser.tablesCollection,
                    storeOverride: baseBrowser.storeOverride
                )
            }
            return baseBrowser
        }()
        let source = SeedingConfiguration.Source(name: url.host ?? url.absoluteString,
                                                 url: url,
                                                 corpusId: config.memoryCorpusId,
                                                 labels: [])
        let seeder = SemanticBrowserSeeder()
        do {
            let metrics = try await seeder.run(source: source, browser: browser) { msg in Task { @MainActor in self.logTrail(msg) } }
            await MainActor.run { self.logTrail("semantic-browser indexed • \(metrics.pagesUpserted) segs=\(metrics.segmentsUpserted)") }
            if await _verifyIndexed(host: url.host) { return true }
            await MainActor.run { self.logTrail("semantic-browser verify • no pages for host; attempting direct import") }
            if await _fallbackFetchAndImport(url: url) { await MainActor.run { self.logTrail("direct import ok • host=\(url.host ?? "?")") }; return true }
            await MainActor.run { self.logTrail("direct import failed • host=\(url.host ?? "?")") }
            return false
        } catch {
            await MainActor.run { self.logTrail("semantic-browser error • \(error)") }
            if await _fallbackFetchAndImport(url: url) { await MainActor.run { self.logTrail("direct import ok • host=\(url.host ?? "?")") }; return true }
            return false
        }
    }

    private func ingestSameHostLinks(seed: URL, count: Int, mode: SeedingConfiguration.Browser.Mode) async -> Int {
        do {
            var req = URLRequest(url: seed); req.httpMethod = "GET"; req.timeoutInterval = 8
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return 0 }
            let html = String(data: data, encoding: .utf8) ?? ""
            let links = Self._filterCrawlable(Self._extractLinks(html: html, base: seed)
                .filter { $0.host == seed.host })
            var taken: Set<String> = []
            var ok = 0
            for u in links {
                if ok >= count { break }
                if !taken.insert(u.absoluteString).inserted { continue }
                if await _ingestSingle(u, overrideMode: mode) { ok += 1 }
            }
            return ok
        } catch { return 0 }
    }

    public func ingestFiles(_ urls: [URL], labels: [String] = []) async -> Bool {
        var anyOK = false
        for u in urls {
            do {
                guard let content = Self._readText(from: u) else {
                    self.logTrail("file import • unsupported or empty: \(u.lastPathComponent)")
                    continue
                }
                let pageId = "file:\(u.lastPathComponent)"
                let title = u.deletingPathExtension().lastPathComponent
                let page = Page(corpusId: config.memoryCorpusId, pageId: pageId, url: u.absoluteString, host: "file", title: title)
                _ = try await store.addPage(page)
                // Chunk large texts into multiple segments to improve retrieval
                let chunks = Self._chunkText(content, maxSegments: 8, targetChars: 420)
                if chunks.isEmpty {
                    let seg = Segment(corpusId: config.memoryCorpusId, segmentId: "\(pageId):0", pageId: pageId, kind: "paragraph", text: content)
                    _ = try await store.addSegment(seg)
                } else {
                    var idx = 0
                    for c in chunks {
                        let seg = Segment(corpusId: config.memoryCorpusId, segmentId: "\(pageId):\(idx)", pageId: pageId, kind: "paragraph", text: c)
                        _ = try await store.addSegment(seg)
                        idx += 1
                    }
                }
                anyOK = true
                self.logTrail("imported file • \(u.lastPathComponent) segs=\(max(1, content.isEmpty ? 0 : Self._chunkText(content, maxSegments: 8, targetChars: 420).count))")
            } catch {
                self.logTrail("file import error • \(error)")
            }
        }
        return anyOK
    }

    // MARK: - File text readers
    private static func _readText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "md", "markdown", "csv", "json", "yaml", "yml", "log":
            return try? String(contentsOf: url)
        case "html", "htm":
            if let html = try? String(contentsOf: url) { return _stripHTML(html) }
            return nil
        case "rtf":
            #if canImport(AppKit)
            if let attr = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                return attr.string
            }
            #endif
            return nil
        case "rtfd":
            #if canImport(AppKit)
            if let data = try? Data(contentsOf: url),
               let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
                return attr.string
            }
            #endif
            return nil
        case "pdf":
            #if canImport(PDFKit)
            if let doc = PDFDocument(url: url) {
                var out = ""
                for i in 0..<(doc.pageCount) {
                    if let page = doc.page(at: i), let s = page.string { out += s + "\n\n" }
                }
                return out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            #endif
            return nil
        default:
            // Last resort: try to read as UTF-8 text
            return try? String(contentsOf: url)
        }
    }

    private func _verifyIndexed(host: String?) async -> Bool {
        guard let host, !host.isEmpty else { return false }
        do {
            let q = Query(filters: ["corpusId": config.memoryCorpusId, "host": host], limit: 1, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
            return resp.total > 0 && !resp.documents.isEmpty
        } catch { return false }
    }

    private func _fallbackFetchAndImport(url: URL) async -> Bool {
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 10
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
            let ctype = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard ctype.contains("text/html") || ctype.contains("text/plain") else { return false }
            let html = String(data: data, encoding: .utf8) ?? ""
            let text = Self._stripHTML(html)
            let pageId = url.absoluteString
            let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path.split(separator: "/").last.map(String.init) ?? (url.host ?? "page")
            let page = Page(corpusId: config.memoryCorpusId, pageId: pageId, url: url.absoluteString, host: url.host ?? "web", title: title)
            _ = try await store.addPage(page)
            let seg = Segment(corpusId: config.memoryCorpusId, segmentId: "\(pageId):0", pageId: pageId, kind: "paragraph", text: text)
            _ = try await store.addSegment(seg)
            return true
        } catch {
            return false
        }
    }

    private static func _stripHTML(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "(?s)<script.*?>.*?</script>", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?s)<style.*?>.*?</style>", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func _chunkText(_ text: String, maxSegments: Int = 5, targetChars: Int = 360) -> [String] {
        let cleaned = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
        if cleaned.isEmpty { return [] }
        let paras = cleaned.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var chunks: [String] = []
        if paras.count >= 2 {
            var current = ""
            for p in paras {
                if current.isEmpty { current = p }
                else if (current.count + 1 + p.count) < (targetChars + targetChars/2) {
                    current += "\n\n" + p
                } else {
                    chunks.append(current)
                    current = p
                }
                if chunks.count >= maxSegments { break }
            }
            if !current.isEmpty && chunks.count < maxSegments { chunks.append(current) }
        } else {
            let sentences = cleaned.replacingOccurrences(of: "\n", with: " ").components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var current = ""
            for s in sentences {
                if current.isEmpty { current = s + "." }
                else if (current.count + 1 + s.count) < (targetChars + targetChars/2) {
                    current += " " + s + "."
                } else {
                    chunks.append(current)
                    current = s + "."
                }
                if chunks.count >= maxSegments { break }
            }
            if !current.isEmpty && chunks.count < maxSegments { chunks.append(current) }
        }
        return chunks.map { String($0.prefix(targetChars + 160)) }
    }

    private static func _extractLinks(html: String, base: URL) -> [URL] {
        var results: [URL] = []
        let pattern = "href=\\\"([^\\\"]+)\\\"|href='([^']+)'"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let ns = html as NSString
            for m in regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) {
                let r1 = m.range(at: 1)
                let r2 = m.range(at: 2)
                let raw: String
                if r1.location != NSNotFound { raw = ns.substring(with: r1) }
                else if r2.location != NSNotFound { raw = ns.substring(with: r2) }
                else { continue }
                guard !raw.hasPrefix("#") else { continue }
                if let u = URL(string: raw, relativeTo: base)?.absoluteURL { results.append(u) }
            }
        }
        return results
    }

    private static func _filterCrawlable(_ links: [URL]) -> [URL] {
        let badExt: Set<String> = [
            "css","js","png","jpg","jpeg","gif","svg","ico","webp","mp4","mp3","mov","pdf","zip","tar","gz","7z","rar","woff","woff2","ttf"
        ]
        func hasBadExt(_ u: URL) -> Bool {
            let ext = u.pathExtension.lowercased()
            return !ext.isEmpty && badExt.contains(ext)
        }
        let banned = ["impressum","hilfe","help","support","kontakt","contact","privacy","datenschutz","about","agb","terms","imprint"]
        return links.filter { u in
            guard ["http","https"].contains(u.scheme?.lowercased() ?? "") else { return false }
            if hasBadExt(u) { return false }
            if u.path.lowercased().contains("/assets/") { return false }
            let path = u.path.lowercased()
            if banned.contains(where: { path.contains($0) }) { return false }
            return true
        }
    }

    private func retrieveHostSnippets(host: String, limit: Int = 5) async -> [String] {
        do {
            // 1) List pages for the host (most recent first if field available)
            var qp = Query(filters: ["corpusId": config.memoryCorpusId, "host": host], limit: 30, offset: 0)
            qp.sort = [("fetchedAt", false)]
            let pageResp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: qp)
            struct PageDoc: Codable { let pageId: String; let title: String? }
            let pages: [PageDoc] = pageResp.documents.compactMap { try? JSONDecoder().decode(PageDoc.self, from: $0) }
            if pages.isEmpty { return [] }
            // 2) Pull the first segment for each page to build quick snippets
            var out: [String] = []
            for p in pages.prefix(limit * 3) {
                let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": p.pageId], limit: 1, offset: 0)
                let segResp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
                struct SegmentDoc: Codable { let text: String }
                if let first = segResp.documents.first, let s = try? JSONDecoder().decode(SegmentDoc.self, from: first) {
                    out.append(trim(s.text, limit: 320))
                }
                if out.count >= limit { break }
            }
            return out
        } catch { return [] }
    }

    private func buildHostSnapshotIfAvailable(host: String, limitPages: Int = 6, limitSegmentsPerPage: Int = 2) async -> String? {
        do {
            var qp = Query(filters: ["corpusId": config.memoryCorpusId, "host": host], limit: limitPages, offset: 0)
            qp.sort = [("fetchedAt", false)]
            let pageResp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: qp)
            struct PageDoc: Codable { let pageId: String; let title: String? }
            let pages: [PageDoc] = pageResp.documents.compactMap { try? JSONDecoder().decode(PageDoc.self, from: $0) }
            guard !pages.isEmpty else { return nil }
            var bullets: [String] = []
            for p in pages {
                let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": p.pageId], limit: limitSegmentsPerPage, offset: 0)
                let segResp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
                struct SegmentDoc: Codable { let text: String }
                for d in segResp.documents {
                    if let s = try? JSONDecoder().decode(SegmentDoc.self, from: d) {
                        bullets.append("• " + trim(s.text, limit: 240))
                    }
                }
            }
            guard !bullets.isEmpty else { return nil }
            let body = bullets.prefix(10).joined(separator: "\n")
            return "Host snapshot (from memory for \(host)):\n\(body)"
        } catch { return nil }
    }

    private func persistReflection(from turn: EngraverChatTurn) async {
        if let base = config.awarenessURL { // primary: delegate to Awareness service
            do {
                let client = AwarenessClient(baseURL: base)
                let req = Components.Schemas.ReflectionRequest(
                    corpusId: config.memoryCorpusId,
                    reflectionId: turn.id.uuidString,
                    question: turn.prompt,
                    content: turn.answer
                )
                let t0 = Date()
                _ = try await client.addReflection(req)
                logTrail("POST /corpus/reflections 200 in \(Int(Date().timeIntervalSince(t0)*1000)) ms")
                await refreshAwareness(reason: "post-reflection")
            } catch {
                logTrail("POST /corpus/reflections error • \(error)")
            }
            return
        }
        // fallback: persist directly in FountainStore
        do {
            let reflection = Reflection(corpusId: config.memoryCorpusId,
                                        reflectionId: turn.id.uuidString,
                                        question: turn.prompt,
                                        content: turn.answer)
            _ = try await store.addReflection(reflection)
            logTrail("STORE /reflections ok")
        } catch { logTrail("STORE /reflections error • \(error)") }
    }

    private func tryAutoBaseline(from turn: EngraverChatTurn) async {
        guard !didAutoBaseline else { return }
        // If Awareness is configured, delegate; else persist directly in store
        let base = config.awarenessURL
        // Build a compact baseline payload
        var lines: [String] = []
        if let sum = vm.awarenessSummaryText, !sum.isEmpty { lines.append(sum) }
        if let hist = vm.awarenessHistorySummary, !hist.isEmpty { lines.append(hist) }
        if let cont = continuityDigest, !cont.isEmpty { lines.append("continuity: " + trim(cont, limit: 320)) }
        let content: String
        if !lines.isEmpty { content = lines.joined(separator: "\n\n") }
        else { content = "auto-baseline: Q=\(trim(turn.prompt, limit: 240))\nA=\(trim(turn.answer, limit: 320))" }
        do {
            // Attempt synthesis from context using the model; fallback to assembled content
            let ctx = InjectedContext(continuity: continuityDigest,
                                      awarenessSummary: vm.awarenessSummaryText,
                                      awarenessHistory: vm.awarenessHistorySummary,
                                      snippets: [],
                                      baselines: [],
                                      drifts: [],
                                      patterns: [])
            let synthesized = await self.synthesizeBaselineText(ctx)
            if let base {
                let client = AwarenessClient(baseURL: base)
                let req = Components.Schemas.BaselineRequest(
                    corpusId: config.memoryCorpusId,
                    baselineId: "baseline-\(Int(Date().timeIntervalSince1970))",
                    content: synthesized ?? content
                )
                let t0 = Date()
                do {
                    _ = try await client.addBaseline(req)
                    didAutoBaseline = true
                    logTrail("POST /corpus/baseline 200 in \(Int(Date().timeIntervalSince(t0)*1000)) ms")
                    lastBaselineText = synthesized ?? content
                    await refreshAwareness(reason: "post-baseline")
                } catch {
                    logTrail("POST /corpus/baseline error • \(error)")
                }
            } else {
                // Persist directly to store when Awareness is not configured
                let baseline = Baseline(corpusId: config.memoryCorpusId,
                                        baselineId: "baseline-\(Int(Date().timeIntervalSince1970))",
                                        content: synthesized ?? content)
                _ = try await store.addBaseline(baseline)
                didAutoBaseline = true
                lastBaselineText = baseline.content
                logTrail("STORE /baselines ok")
            }
        } catch {
            logTrail("POST /corpus/baseline error • \(error)")
        }
    }

    private func tryAutoPatternsAndDrift() async {
        guard let awareURL = config.awarenessURL else {
            // Awareness not configured — still synthesise and persist to FountainStore.
            // Prepare context
            let ctx = InjectedContext(continuity: continuityDigest,
                                      awarenessSummary: vm.awarenessSummaryText,
                                      awarenessHistory: vm.awarenessHistorySummary,
                                      snippets: [],
                                      baselines: [],
                                      drifts: [],
                                      patterns: [])
            let newBaseline = await synthesizeBaselineText(ctx) ?? vm.awarenessSummaryText ?? ""
            if !newBaseline.isEmpty && lastBaselineText != nil {
                let drift = await synthesizeDriftText(old: lastBaselineText ?? "", new: newBaseline)
                if let drift, !drift.isEmpty {
                    do { _ = try await store.addDrift(Drift(corpusId: config.memoryCorpusId, driftId: "drift-\(Int(Date().timeIntervalSince1970))", content: drift)); logTrail("STORE /drifts ok") } catch { logTrail("STORE /drifts error • \(error)") }
                }
            }
            if let patterns = await synthesizePatternsText(ctx), !patterns.isEmpty {
                do { _ = try await store.addPatterns(Patterns(corpusId: config.memoryCorpusId, patternsId: "patterns-\(Int(Date().timeIntervalSince1970))", content: patterns)); logTrail("STORE /patterns ok") } catch { logTrail("STORE /patterns error • \(error)") }
            }
            lastBaselineText = newBaseline
            return
        }
        // Prepare context
        let ctx = InjectedContext(continuity: continuityDigest,
                                  awarenessSummary: vm.awarenessSummaryText,
                                  awarenessHistory: vm.awarenessHistorySummary,
                                  snippets: [],
                                  baselines: [],
                                  drifts: [],
                                  patterns: [])
        // Synthesize baseline snapshot
        let newBaseline = await synthesizeBaselineText(ctx) ?? vm.awarenessSummaryText ?? ""
        if !newBaseline.isEmpty && lastBaselineText != nil {
            let drift = await synthesizeDriftText(old: lastBaselineText ?? "", new: newBaseline)
            if let drift, !drift.isEmpty {
                await postDrift(to: awareURL, content: drift)
            }
        }
        // Patterns regardless of drift
        if let patterns = await synthesizePatternsText(ctx), !patterns.isEmpty {
            await postPatterns(to: awareURL, content: patterns)
        }
        lastBaselineText = newBaseline
        await refreshAwareness(reason: "post-patterns-drift")
    }

    private func synthesizeDriftText(old: String, new: String) async -> String? {
        guard let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                              openAIEndpoint: config.openAIEndpoint,
                                                              localEndpoint: nil) else { return nil }
        let client = OpenAICompatibleChatProvider(apiKey: selection.usesAPIKey ? config.openAIAPIKey : nil,
                                                  endpoint: selection.endpoint)
        let system = "You are Drift Inspector. Compare Baseline A vs Baseline B and output 3–6 concise drift bullets capturing real changes only."
        let materials = "Baseline A:\n\(old)\n\nBaseline B:\n\(new)"
        let req = CoreChatRequest(model: config.model, messages: [
            CoreChatMessage(role: .system, content: system),
            CoreChatMessage(role: .user, content: materials)
        ])
        do {
            let resp = try await client.complete(request: req)
            return resp.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { logTrail("POST /openai/chat error • \(error)"); return nil }
    }

    private func synthesizePatternsText(_ ctx: InjectedContext) async -> String? {
        guard let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                              openAIEndpoint: config.openAIEndpoint,
                                                              localEndpoint: nil) else { return nil }
        let client = OpenAICompatibleChatProvider(apiKey: selection.usesAPIKey ? config.openAIAPIKey : nil,
                                                  endpoint: selection.endpoint)
        let system = "You are Patterns. From summary/history below, produce 3–6 recurring patterns (bulleted, neutral, source-agnostic)."
        let materials = "Summary:\n\(ctx.awarenessSummary ?? "")\n\nHistory:\n\(ctx.awarenessHistory ?? "")"
        let req = CoreChatRequest(model: config.model, messages: [
            CoreChatMessage(role: .system, content: system),
            CoreChatMessage(role: .user, content: materials)
        ])
        do {
            let resp = try await client.complete(request: req)
            return resp.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { logTrail("POST /openai/chat error • \(error)"); return nil }
    }

    private func postDrift(to base: URL, content: String) async {
        do {
            let client = AwarenessClient(baseURL: base)
            let req = Components.Schemas.DriftRequest(corpusId: config.memoryCorpusId,
                                                      driftId: "drift-\(Int(Date().timeIntervalSince1970))",
                                                      content: content)
            _ = try await client.addDrift(req)
            logTrail("POST /corpus/drift 200")
        } catch {
            logTrail("POST /corpus/drift error • \(error)")
            // Fallback: store directly if Awareness fails
            do { _ = try await store.addDrift(Drift(corpusId: config.memoryCorpusId, driftId: "drift-\(Int(Date().timeIntervalSince1970))", content: content)); logTrail("STORE /drifts ok") } catch { logTrail("STORE /drifts error • \(error)") }
        }
    }

    private func postPatterns(to base: URL, content: String) async {
        do {
            let client = AwarenessClient(baseURL: base)
            let req = Components.Schemas.PatternsRequest(corpusId: config.memoryCorpusId,
                                                         patternsId: "patterns-\(Int(Date().timeIntervalSince1970))",
                                                         content: content)
            _ = try await client.addPatterns(req)
            logTrail("POST /corpus/patterns 200")
        } catch {
            logTrail("POST /corpus/patterns error • \(error)")
            // Fallback: store directly if Awareness fails
            do { _ = try await store.addPatterns(Patterns(corpusId: config.memoryCorpusId, patternsId: "patterns-\(Int(Date().timeIntervalSince1970))", content: content)); logTrail("STORE /patterns ok") } catch { logTrail("STORE /patterns error • \(error)") }
        }
    }

    // MARK: - Store helpers
    private static func makeDiskStoreClient() -> DiskFountainStoreClient? {
        // Resolve store dir with priority:
        // 1) FOUNTAINSTORE_DIR (used by dev-up/launcher for shared services)
        // 2) ENGRAVER_STORE_PATH (legacy override)
        // 3) ~/.fountain/engraver-store (fallback)
        let env = ProcessInfo.processInfo.environment
        let raw = (env["FOUNTAINSTORE_DIR"] ?? env["ENGRAVER_STORE_PATH"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if let raw, !raw.isEmpty {
            if raw.hasPrefix("~") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let suffix = raw.dropFirst()
                url = home.appendingPathComponent(String(suffix), isDirectory: true)
            } else {
                url = URL(fileURLWithPath: raw, isDirectory: true)
            }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            url = home.appendingPathComponent(".fountain", isDirectory: true).appendingPathComponent("engraver-store", isDirectory: true)
        }
        return try? DiskFountainStoreClient(rootDirectory: url)
    }

    // MARK: - Role Health Check via Gateway
    private func ensureRolesViaGateway() async {
        guard let gw = config.gatewayURL else { return }
        let rest = RESTClient(baseURL: gw, defaultHeaders: ["Accept": "application/json", "Content-Type": "application/json"])
        let body: [String: Any] = ["corpusId": config.memoryCorpusId]
        do {
            // POST /role-health-check/reflect
            if let url1 = rest.buildURL(path: "/role-health-check/reflect") {
                let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                let t0 = Date()
                _ = try await rest.send(APIRequest(method: .POST, url: url1, headers: [:], body: data))
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                logTrail("roles.reflect ok • ms=\(ms)")
            }
            // POST /role-health-check/promote
            if let url2 = rest.buildURL(path: "/role-health-check/promote") {
                let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                let t1 = Date()
                _ = try await rest.send(APIRequest(method: .POST, url: url2, headers: [:], body: data))
                let ms = Int(Date().timeIntervalSince(t1) * 1000)
                logTrail("roles.promote ok • ms=\(ms)")
            }
        } catch {
            logTrail("roles.health-check error • \(error)")
        }
    }
}

// MARK: - Memory helpers and connection test
@MainActor public protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
extension URLSession: HTTPClient {}

extension MemChatController {
    public struct PageItem: Identifiable, Sendable, Hashable, Equatable { public let id: String; public let title: String }

    public func listMemoryPages(limit: Int = 100) async -> [PageItem] {
        do {
            let q = Query(filters: ["corpusId": config.memoryCorpusId], limit: limit, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: q)
            struct PageDoc: Codable { let pageId: String; let title: String }
            return resp.documents.compactMap { data in
                (try? JSONDecoder().decode(PageDoc.self, from: data)).map { PageItem(id: $0.pageId, title: $0.title) }
            }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch { return [] }
    }

    public func fetchPageText(pageId: String) async -> String? {
        do {
            let q = Query(filters: ["corpusId": config.memoryCorpusId, "pageId": pageId], limit: 50, offset: 0)
            let resp = try await store.query(corpusId: config.memoryCorpusId, collection: "segments", query: q)
            struct Segment: Codable { let text: String }
            if let first = resp.documents.first, let seg = try? JSONDecoder().decode(Segment.self, from: first) { return seg.text }
            return nil
        } catch { return nil }
    }

    public func loadPlanText() async -> String? { await fetchPageText(pageId: "plan:memchat-features") }

    public enum ConnectionStatus: Equatable, Sendable { case ok(String), fail(String) }
    public func testConnection() async -> ConnectionStatus {
        if let gw = config.gatewayURL {
            var req = URLRequest(url: gw.appending(path: "/metrics"))
            req.httpMethod = "GET"; req.timeoutInterval = 3.0
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) { return .ok("gateway") }
                return .fail("Gateway HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
            } catch { return .fail(error.localizedDescription) }
        }
        let provider = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                       openAIEndpoint: config.openAIEndpoint,
                                                       localEndpoint: config.localCompatibleEndpoint)
        guard let provider else { return .fail("No provider configured") }
        let apiKey = provider.usesAPIKey ? (config.openAIAPIKey ?? "") : nil
        return await ConnectionTester.test(apiKey: apiKey, endpoint: provider.endpoint)
    }

    /// Performs a live chat roundtrip against OpenAI and returns a short status.
    /// Uses a deterministic prompt and non-streaming call; does not mutate chat state.
    public func testLiveChatRoundtrip() async -> ConnectionStatus {
        let req = ChatRequest(model: config.model, messages: [.init(role: .user, content: "Respond with the single word: ok")])
        if let gw = config.gatewayURL {
            let client = GatewayProvider.make(baseURL: gw) { nil }
            do {
                let resp = try await client.complete(request: req)
                let preview = resp.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { return .fail("Empty reply from gateway") }
                return .ok(preview)
            } catch { return .fail(String(describing: error)) }
        } else {
            guard let selection = ProviderResolver.selectProvider(apiKey: config.openAIAPIKey,
                                                                  openAIEndpoint: config.openAIEndpoint,
                                                                  localEndpoint: nil) else {
                return .fail("OPENAI_API_KEY not configured")
            }
            let client = OpenAICompatibleChatProvider(apiKey: config.openAIAPIKey, endpoint: selection.endpoint)
            do {
                let resp = try await client.complete(request: req)
                let preview = resp.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { return .fail("Empty reply from OpenAI") }
                return .ok(preview)
            } catch { return .fail(String(describing: error)) }
        }
    }
}

// MARK: - Corpus management
extension MemChatController {
    /// List available corpora from the backing store.
    public func listCorpora(limit: Int = 10_000) async -> [String] {
        do { let (_, list) = try await store.listCorpora(limit: limit, offset: 0); return list } catch { return [] }
    }

    /// Create a new corpus. Returns true on success.
    public func createCorpus(id: String) async -> Bool {
        do { _ = try await store.createCorpus(id); return true } catch { return false }
    }

    /// Load baselines directly from the store (no model involved).
    public func loadBaselines(limit: Int = 100) async -> [BaselineItem] {
        do {
            let (_, items) = try await store.listBaselines(corpusId: config.memoryCorpusId, limit: 1000, offset: 0)
            let sorted = items.sorted { $0.ts > $1.ts }
            return Array(sorted.prefix(limit)).map { BaselineItem(id: $0.baselineId, content: $0.content, ts: $0.ts) }
        } catch {
            return []
        }
    }

    /// Load drifts directly from the store.
    public func loadDrifts(limit: Int = 100) async -> [DriftItem] {
        do {
            let (_, items) = try await store.listDrifts(corpusId: config.memoryCorpusId, limit: 1000, offset: 0)
            let sorted = items.sorted { $0.ts > $1.ts }
            return Array(sorted.prefix(limit)).map { DriftItem(id: $0.driftId, content: $0.content, ts: $0.ts) }
        } catch { return [] }
    }

    /// Load patterns directly from the store.
    public func loadPatterns(limit: Int = 100) async -> [PatternsItem] {
        do {
            let (_, items) = try await store.listPatterns(corpusId: config.memoryCorpusId, limit: 1000, offset: 0)
            let sorted = items.sorted { $0.ts > $1.ts }
            return Array(sorted.prefix(limit)).map { PatternsItem(id: $0.patternsId, content: $0.content, ts: $0.ts) }
        } catch { return [] }
    }

    /// List distinct hosts present in the pages collection for the current corpus.
    public func listHosts(limit: Int = 2000) async -> [String] {
        do {
            var offset = 0
            var found = Set<String>()
            while true {
                let (total, pages) = try await store.listPages(corpusId: config.memoryCorpusId, limit: 500, offset: offset)
                for p in pages { if !p.host.isEmpty { found.insert(p.host) } }
                offset += pages.count
                if offset >= total || pages.isEmpty { break }
                if found.count >= limit { break }
            }
            return found.sorted()
        } catch { return [] }
    }

    /// Load coverage (pages/segments and recent titles) per host.
    public func loadHostCoverage(limitPerHost: Int = 8) async -> [HostCoverageItem] {
        let hosts = await listHosts()
        var out: [HostCoverageItem] = []
        for h in hosts {
            let cov = await fetchHostCoverage(host: h, limit: limitPerHost)
            let sources = cov.recent.map { HostCoverageItem.Source(title: $0.title, url: $0.url) }
            out.append(HostCoverageItem(host: h, pages: cov.pages, segments: cov.segments, recent: sources))
        }
        return out.sorted { $0.pages > $1.pages }
    }

    /// Evidence preview for a host (text + citations) for inspector UI.
    public func evidencePreview(host: String, depthLevel: Int = 2) async -> [(title: String, url: String, text: String)] {
        let ev = await fetchCitedEvidence(host: host, depthLevel: depthLevel)
        return ev.map { (title: $0.title, url: $0.url, text: $0.text) }
    }

    /// Coverage summary for a single host.
    public func coverageForHost(host: String, limit: Int = 8) async -> HostCoverageItem {
        let cov = await fetchHostCoverage(host: host, limit: limit)
        let sources = cov.recent.map { HostCoverageItem.Source(title: $0.title, url: $0.url) }
        return HostCoverageItem(host: host, pages: cov.pages, segments: cov.segments, recent: sources)
    }

    /// Build a visual evidence map by browsing a recent page for the host via the Semantic Browser.
    /// Returns the dev asset URL and normalized overlays with an approximate coverage percent in 0..1.
    public func buildEvidenceMap(host: String) async -> (imageURL: URL, overlays: [EvidenceMapView.Overlay], coverage: Double)? {
        // Resolve a representative URL: prefer most recent stored page for host; fallback to https://<host>
        let recent = await fetchHostCoverage(host: host, limit: 1).recent
        let targetURL: URL = (recent.first.flatMap { URL(string: $0.url) }) ?? URL(string: "https://\(host)")!

        // Configure SemanticBrowserAPI client
        guard let browser = browserConfig else { return nil }
        var defaultHeaders: [String: String] = [:]
        if let apiKey = browser.apiKey, !apiKey.isEmpty { defaultHeaders["X-API-Key"] = apiKey }
        let transport = URLSessionTransport()
        let middlewares = OpenAPIClientFactory.defaultMiddlewares(defaultHeaders: defaultHeaders)
        let client = SemanticBrowserAPI.Client(serverURL: browser.baseURL, transport: transport, middlewares: middlewares)

        // Compose request with dev-friendly options (no indexing; artifacts not required)
        let wait = SemanticBrowserAPI.Components.Schemas.WaitPolicy(strategy: .networkIdle, networkIdleMs: 500, selector: nil, maxWaitMs: 12000)
        let req = SemanticBrowserAPI.Components.Schemas.BrowseRequest(url: targetURL.absoluteString, wait: wait, mode: .standard, index: .init(enabled: false), storeArtifacts: false, labels: nil)
        do {
            let out = try await client.browseAndDissect(.init(body: .json(req)))
            guard case .ok(let ok) = out else { return nil }
            let body = try ok.body.json
            let snapshot = body.snapshot
            guard let image = snapshot.rendered.image, let analysis = body.analysis, let imageId = image.imageId else { return nil }
            // Convert rects keyed to this image into overlays
            var overlays: [EvidenceMapView.Overlay] = []
            for b in analysis.blocks {
                if let rects = b.rects {
                    for (i, r) in rects.enumerated() {
                        if r.imageId == imageId {
                            let rect = CGRect(x: CGFloat(r.x ?? 0), y: CGFloat(r.y ?? 0), width: CGFloat(r.w ?? 0), height: CGFloat(r.h ?? 0))
                            guard rect.width > 0, rect.height > 0 else { continue }
                            overlays.append(.init(id: "\(b.id)-\(i)", rect: rect, color: .green))
                        }
                    }
                }
            }
            // Build asset fetch URL (dev route)
            let imgURL = browser.baseURL.appendingPathComponent("assets").appendingPathComponent("\(imageId).png")
            let coverage = Double(VisualCoverageUtils.unionAreaNormalized(overlays.map { $0.rect }))
            return (imageURL: imgURL, overlays: overlays, coverage: max(0.0, min(1.0, coverage)))
        } catch {
            return nil
        }
    }

    /// Learn a few more pages for a host by crawling same-host links starting from the most recent page.
    /// Returns number of pages successfully ingested.
    public func learnMoreForHost(host: String, count: Int = 3, modeLabel: String = "standard") async -> Int {
        do {
            var qp = Query(filters: ["corpusId": config.memoryCorpusId, "host": host], limit: 1, offset: 0)
            qp.sort = [("fetchedAt", false)]
            let pagesResp = try await store.query(corpusId: config.memoryCorpusId, collection: "pages", query: qp)
            struct PageDoc: Codable { let url: String }
            guard let first = pagesResp.documents.first,
                  let page = try? JSONDecoder().decode(PageDoc.self, from: first),
                  let seed = URL(string: page.url) else { return 0 }
            let mode: SeedingConfiguration.Browser.Mode = {
                switch modeLabel.lowercased() { case "quick": return .quick; case "deep": return .deep; default: return .standard }
            }()
            let n = await ingestSameHostLinks(seed: seed, count: max(1, count), mode: mode)
            if n > 0 { await ensureHostMemoryArtifacts(host: host) }
            return n
        } catch { return 0 }
    }

    /// Merge a set of source corpora into a new or existing target corpus.
    /// When IDs collide, this method prefixes identifiers with the source corpus ID.
    public func mergeCorpora(sources: [String], into targetCorpusId: String) async throws {
        guard !sources.isEmpty else { return }
        // Ensure target corpus exists
        _ = try? await store.createCorpus(targetCorpusId)

        // Helper: pageId mapping per source after prefixing
        func pref(_ src: String, _ id: String) -> String { "\(src):\(id)" }

        // Copy pages and build pageId maps
        for src in sources {
            // Pages
            var offset = 0
            let pageLimit = 500
            var pageMap: [String: String] = [:]
            while true {
                do {
                    let (total, pages) = try await store.listPages(corpusId: src, limit: pageLimit, offset: offset)
                    for p in pages {
                        let newId = pref(src, p.pageId)
                        pageMap[p.pageId] = newId
                        let page = Page(corpusId: targetCorpusId, pageId: newId, url: p.url, host: p.host, title: p.title)
                        _ = try await store.addPage(page)
                    }
                    offset += pages.count
                    if offset >= total || pages.isEmpty { break }
                } catch { break }
            }

            // Segments
            offset = 0
            let segLimit = 500
            while true {
                do {
                    let (total, segments) = try await store.listSegments(corpusId: src, limit: segLimit, offset: offset)
                    for s in segments {
                        let newSegId = pref(src, s.segmentId)
                        let newPageId = pageMap[s.pageId] ?? pref(src, s.pageId)
                        let seg = Segment(corpusId: targetCorpusId, segmentId: newSegId, pageId: newPageId, kind: s.kind, text: s.text)
                        _ = try await store.addSegment(seg)
                    }
                    offset += segments.count
                    if offset >= total || segments.isEmpty { break }
                } catch { break }
            }

            // Entities
            offset = 0
            let entLimit = 500
            while true {
                do {
                    let (total, entities) = try await store.listEntities(corpusId: src, limit: entLimit, offset: offset)
                    for e in entities {
                        let newId = pref(src, e.entityId)
                        let ent = Entity(corpusId: targetCorpusId, entityId: newId, name: e.name, type: e.type)
                        _ = try await store.addEntity(ent)
                    }
                    offset += entities.count
                    if offset >= total || entities.isEmpty { break }
                } catch { break }
            }

            // Tables
            offset = 0
            let tblLimit = 250
            while true {
                do {
                    let (total, tables) = try await store.listTables(corpusId: src, limit: tblLimit, offset: offset)
                    for t in tables {
                        let newId = pref(src, t.tableId)
                        let newPageId = pageMap[t.pageId] ?? pref(src, t.pageId)
                        let tbl = Table(corpusId: targetCorpusId, tableId: newId, pageId: newPageId, csv: t.csv)
                        _ = try await store.addTable(tbl)
                    }
                    offset += tables.count
                    if offset >= total || tables.isEmpty { break }
                } catch { break }
            }

            // Baselines
            offset = 0
            let baseLimit = 250
            while true {
                do {
                    let (total, baselines) = try await store.listBaselines(corpusId: src, limit: baseLimit, offset: offset)
                    for b in baselines {
                        let newId = pref(src, b.baselineId)
                        let rec = Baseline(corpusId: targetCorpusId, baselineId: newId, content: b.content, ts: b.ts)
                        _ = try await store.addBaseline(rec)
                    }
                    offset += baselines.count
                    if offset >= total || baselines.isEmpty { break }
                } catch { break }
            }

            // Reflections
            offset = 0
            let reflLimit = 250
            while true {
                do {
                    let (total, reflections) = try await store.listReflections(corpusId: src, limit: reflLimit, offset: offset)
                    for r in reflections {
                        let newId = pref(src, r.reflectionId)
                        let rec = Reflection(corpusId: targetCorpusId, reflectionId: newId, question: r.question, content: r.content, ts: r.ts)
                        _ = try await store.addReflection(rec)
                    }
                    offset += reflections.count
                    if offset >= total || reflections.isEmpty { break }
                } catch { break }
            }

            // Drifts
            offset = 0
            let driftLimit = 250
            while true {
                do {
                    let (total, drifts) = try await store.listDrifts(corpusId: src, limit: driftLimit, offset: offset)
                    for d in drifts {
                        let newId = pref(src, d.driftId)
                        let rec = Drift(corpusId: targetCorpusId, driftId: newId, content: d.content, ts: d.ts)
                        _ = try await store.addDrift(rec)
                    }
                    offset += drifts.count
                    if offset >= total || drifts.isEmpty { break }
                } catch { break }
            }

            // Patterns
            offset = 0
            let patLimit = 250
            while true {
                do {
                    let (total, patterns) = try await store.listPatterns(corpusId: src, limit: patLimit, offset: offset)
                    for p in patterns {
                        let newId = pref(src, p.patternsId)
                        let rec = Patterns(corpusId: targetCorpusId, patternsId: newId, content: p.content, ts: p.ts)
                        _ = try await store.addPatterns(rec)
                    }
                    offset += patterns.count
                    if offset >= total || patterns.isEmpty { break }
                } catch { break }
            }
        }
    }
}
