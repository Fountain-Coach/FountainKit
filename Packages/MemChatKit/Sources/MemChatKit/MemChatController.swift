import Foundation
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

/// Public facade for embedding MemChat in host apps.
/// Wraps EngraverChatViewModel and enforces per-chat corpus isolation while
/// retrieving memory from a selected corpus.
@MainActor
public final class MemChatController: ObservableObject {
    public let config: MemChatConfiguration

    // Expose a subset of EngraverChatViewModel for host apps.
    @Published public private(set) var turns: [EngraverChatTurn] = []
    @Published public private(set) var streamingText: String = ""
    @Published public private(set) var streamingTokens: [String] = []
    @Published public private(set) var state: EngraverChatState = .idle
    @Published public private(set) var chatCorpusId: String
    @Published public private(set) var providerLabel: String = ""
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var memoryTrail: [String] = []
    @Published public private(set) var lastInjectedContext: InjectedContext? = nil
    @Published public private(set) var turnContext: [UUID: InjectedContext] = [:]

    private let vm: EngraverChatViewModel
    private let store: FountainStoreClient
    private var continuityDigest: String? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var didAutoBaseline: Bool = false
    private var pendingContext: InjectedContext? = nil
    private var lastBaselineText: String? = nil
    private var analysisCounter: Int = 0

    public struct InjectedContext: Sendable, Equatable {
        public let continuity: String?
        public let awarenessSummary: String?
        public let awarenessHistory: String?
        public let snippets: [String]
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
            baseURL: URL(string: ProcessInfo.processInfo.environment["SEMANTIC_BROWSER_URL"] ?? "http://127.0.0.1:8003")!,
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

        Task {
            await self.loadContinuityDigest()
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

    public func send(_ text: String) {
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

            // Retrieve memory snippets (with a broad fallback)
            var snippets = await self.retrieveMemorySnippets(matching: text, limit: 5)
            if snippets.isEmpty { snippets = await self.retrieveMemorySnippets(matching: "", limit: 5) }

            var enriched = base
            if !snippets.isEmpty {
                let list = snippets.map { "• \($0)" }.joined(separator: "\n")
                enriched.append("Memory snippets (from corpus \(self.config.memoryCorpusId)):\n\(list)")
                self.logTrail("MEMORY inject • snippets=\(snippets.count) summary=\(self.vm.awarenessSummaryText?.count ?? 0)")
            } else {
                self.logTrail("MEMORY inject • snippets=0 summary=\(self.vm.awarenessSummaryText?.count ?? 0)")
            }

            // Publish inspector context
            let ctx = InjectedContext(
                continuity: self.continuityDigest,
                awarenessSummary: self.vm.awarenessSummaryText,
                awarenessHistory: self.vm.awarenessHistorySummary,
                snippets: snippets
            )
            self.lastInjectedContext = ctx
            self.pendingContext = ctx

            let sys = self.vm.makeSystemPrompts(base: enriched)
            await MainActor.run {
                self.vm.send(prompt: text, systemPrompts: sys, preferStreaming: true, corpusOverride: self.chatCorpusId)
            }
        }
    }

    private func trim(_ s: String, limit: Int = 600) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        return String(t.prefix(limit - 1)) + "…"
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

    private func persistReflection(from turn: EngraverChatTurn) async {
        if let base = config.awarenessURL { // primary: delegate to Awareness service
            do {
                var req = URLRequest(url: base.appending(path: "/corpus/reflections"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "corpusId": config.memoryCorpusId,
                    "reflectionId": turn.id.uuidString,
                    "question": turn.prompt,
                    "content": turn.answer
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                let t0 = Date()
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(code) {
                    logTrail("POST /corpus/reflections \(code) in \(Int(Date().timeIntervalSince(t0)*1000)) ms")
                    await refreshAwareness(reason: "post-reflection")
                } else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    logTrail("POST /corpus/reflections \(code) • \(text)")
                }
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
                                      snippets: [])
            let synthesized = await self.synthesizeBaselineText(ctx)
            if let base {
                var req = URLRequest(url: base.appending(path: "/corpus/baseline"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "corpusId": config.memoryCorpusId,
                    "baselineId": "baseline-\(Int(Date().timeIntervalSince1970))",
                    "content": synthesized ?? content
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                let t0 = Date()
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(code) {
                    didAutoBaseline = true
                    logTrail("POST /corpus/baseline \(code) in \(Int(Date().timeIntervalSince(t0)*1000)) ms")
                    lastBaselineText = synthesized ?? content
                    await refreshAwareness(reason: "post-baseline")
                } else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    logTrail("POST /corpus/baseline \(code) • \(text)")
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
                                      snippets: [])
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
                                  snippets: [])
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
        // Follow Engraver defaults for store location to keep data unified.
        let env = ProcessInfo.processInfo.environment
        let path = env["ENGRAVER_STORE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if let raw = path, !raw.isEmpty {
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
