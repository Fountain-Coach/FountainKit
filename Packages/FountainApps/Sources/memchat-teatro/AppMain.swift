import SwiftUI
import MemChatKit
import SecretStore
import LauncherSignature

@main
struct MemChatTeatroApp: App {
    @State private var config: MemChatConfiguration
    @StateObject private var controllerHolder: ControllerHolder
    @State private var showSettings = false

    init() {
        verifyLauncherSignature()
        let env = ProcessInfo.processInfo.environment
        let memory = env["MEMORY_CORPUS_ID"] ?? "memchat-app"
        #if canImport(Security)
        let store = KeychainStore(service: "FountainAI")
        let keyData = try? store.retrieveSecret(for: "OPENAI_API_KEY")
        let key = keyData.flatMap { String(data: $0, encoding: .utf8) }
        #else
        let key: String? = nil
        #endif
        let initial = MemChatConfiguration(
            memoryCorpusId: memory,
            model: "gpt-4o-mini",
            openAIAPIKey: key,
            openAIEndpoint: nil,
            localCompatibleEndpoint: nil,
            deepSynthesis: true
        )
        _config = State(initialValue: initial)
        _controllerHolder = StateObject(wrappedValue: ControllerHolder(initial: initial))
    }

    var body: some Scene {
        WindowGroup {
            MemChatTeatroRootView(
                config: $config,
                controllerHolder: controllerHolder,
                openSettings: { showSettings = true }
            )
            .frame(minWidth: 720, minHeight: 520)
            .sheet(isPresented: $showSettings) {
                MemChatTeatroSettingsView(
                    memoryCorpusId: config.memoryCorpusId,
                    openAIKey: config.openAIAPIKey ?? "",
                    model: config.model,
                    useGateway: config.gatewayURL != nil,
                    gatewayURLString: config.gatewayURL?.absoluteString ?? (ProcessInfo.processInfo.environment["FOUNTAIN_GATEWAY_URL"] ?? "http://127.0.0.1:8010"),
                    evidenceDepth: config.depthLevel
                ) { newCfg in
                    config = newCfg
                    controllerHolder.recreate(with: newCfg)
                }
            }
        }
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: MemChatController
    init(initial: MemChatConfiguration) {
        controller = MemChatController(config: initial)
    }
    func recreate(with cfg: MemChatConfiguration) {
        controller = MemChatController(config: cfg)
    }
}

struct MemChatTeatroRootView: View {
    @Binding var config: MemChatConfiguration
    @ObservedObject var controllerHolder: ControllerHolder
    var openSettings: () -> Void

    @State private var connectionStatus: String = ""
    @State private var didRunSelfCheck = false
    @State private var showAddURLSheet = false
    @State private var addURLString: String = ""
    @State private var addURLStatus: String = ""
    @State private var addURLDepth: Int = 2
    @State private var addURLMaxPages: Int = 12
    @State private var addURLMode: String = "standard"
    @State private var showBaselines = false
    @State private var baselines: [MemChatController.BaselineItem] = []
    @State private var showDrifts = false
    @State private var drifts: [MemChatController.DriftItem] = []
    @State private var showPatterns = false
    @State private var patterns: [MemChatController.PatternsItem] = []
    @State private var showBuildBaseline = false
    @State private var hosts: [String] = []
    @State private var selectedHost: String = ""
    @State private var buildLevel: Int = 2
    @State private var buildStatus: String = ""
    @State private var buildWorking: Bool = false
    @State private var showHosts = false
    @State private var hostsCoverage: [MemChatController.HostCoverageItem] = []
    @State private var topHosts: [MemChatController.HostCoverageItem] = []
    @State private var showEvidence = false
    @State private var evidenceHost: String = ""
    @State private var evidenceDepth: Int = 2
    @State private var evidenceItems: [(title: String, url: String, text: String)] = []
    @State private var showMap = false
    @State private var mapOverlays: [EvidenceMapView.Overlay] = []
    @State private var mapCovered: [EvidenceMapView.Overlay] = []
    @State private var mapMissing: [EvidenceMapView.Overlay] = []
    @State private var mapStale: [EvidenceMapView.Overlay] = []
    @State private var mapPageId: String = ""
    @State private var staleDays: Int = 60
    @State private var serverClassify: Bool = true
    @State private var selectedRect: CGRect? = nil
    @State private var mapImageURL: URL? = nil
    @State private var mapCoverage: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("MemChat Teatro").font(.headline)
                Divider().frame(height: 18)
                Text(config.memoryCorpusId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(controllerHolder.controller.providerLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("Add Memory") {
                    Button("Learn Site…") { showAddURLSheet = true }
                    Button("Import Files…") { importFiles() }
                }
                Button("Test") { Task { await testConnection() } }
                Button("Live Test") { Task { await testLiveChat() } }
                Button("Baselines") { Task { await openBaselines() } }
                Button("Drifts") { Task { await openDrifts() } }
                Button("Patterns") { Task { await openPatterns() } }
                Button("Build Baseline") { Task { await openBuildBaseline() } }
                Button("Hosts") { Task { await openHosts() } }
                Button("Settings") { openSettings() }
            }
            .padding(12)

            if !connectionStatus.isEmpty {
                Text(connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            Divider()

            // Mini host coverage summary (top 3)
            if !topHosts.isEmpty {
                HStack(spacing: 10) {
                    Text("Top hosts:").font(.caption).foregroundStyle(.secondary)
                    ForEach(topHosts.prefix(3)) { h in
                        Button(action: { Task { await openEvidence(host: h.host) } }) {
                            Text("\(h.host) [p:\(h.pages) s:\(h.segments)]").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button("Refresh") { Task { await refreshTopHosts() } }.font(.caption)
                }
                .padding(.horizontal, 12)
            }

            MemChatTeatroView(controller: controllerHolder.controller)
        }
        .task {
            if !didRunSelfCheck {
                didRunSelfCheck = true
                await testLiveChat()
            }
            await refreshTopHosts()
        }
        .sheet(isPresented: $showAddURLSheet) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Learn Site").font(.title3).bold(); Spacer(); Button("Close") { showAddURLSheet = false } }
                TextField("https://…", text: $addURLString).textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    Picker("Mode", selection: $addURLMode) {
                        Text("Quick").tag("quick"); Text("Standard").tag("standard"); Text("Deep").tag("deep")
                    }.labelsHidden()
                    Stepper("Depth: \(addURLDepth)", value: $addURLDepth, in: 0...5)
                    Stepper("Pages: \(addURLMaxPages)", value: $addURLMaxPages, in: 1...50)
                }
                if let p = controllerHolder.controller.learnProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(max(p.visited,1)), total: Double(max(p.target,1))).controlSize(.small)
                        Text("Visited \(p.visited)/\(p.target) • Pages \(p.pages) • Segments \(p.segs)").font(.caption).foregroundStyle(.secondary)
                    }
                } else if !addURLStatus.isEmpty {
                    Text(addURLStatus).font(.caption).foregroundStyle(.secondary)
                }
                HStack { Spacer(); Button("Learn") { Task { await indexURL() } }.disabled(addURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .padding(12)
            .frame(minWidth: 460)
        }
        .sheet(isPresented: $showBaselines) {
            TeatroBaselinesSheet(items: baselines) { showBaselines = false }
                .frame(minWidth: 560, minHeight: 420)
                .padding(12)
        }
        .sheet(isPresented: $showDrifts) {
            TeatroDriftsSheet(items: drifts) { showDrifts = false }
                .frame(minWidth: 560, minHeight: 420)
                .padding(12)
        }
        .sheet(isPresented: $showPatterns) {
            TeatroPatternsSheet(items: patterns) { showPatterns = false }
                .frame(minWidth: 560, minHeight: 420)
                .padding(12)
        }
        .sheet(isPresented: $showBuildBaseline) {
            TeatroBuildBaselineSheet(hosts: hosts,
                                     selectedHost: $selectedHost,
                                     level: $buildLevel,
                                     status: $buildStatus,
                                     working: $buildWorking,
                                     onBuild: {
                                        Task {
                                            buildWorking = true
                                            buildStatus = "Building…"
                                            let ok = await controllerHolder.controller.buildBaselineAndArtifacts(for: selectedHost, level: buildLevel)
                                            buildWorking = false
                                            buildStatus = ok ? "Baseline built." : "No evidence yet for host."
                                        }
                                     },
                                     onClose: { showBuildBaseline = false })
                .frame(minWidth: 560, minHeight: 340)
                .padding(12)
        }
        .sheet(isPresented: $showHosts) {
            TeatroHostsSheet(
                controller: controllerHolder.controller,
                items: hostsCoverage,
                openEvidence: { host in
                    showHosts = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Task { await openEvidence(host: host) } }
                },
                onClose: { showHosts = false }
            )
                .frame(minWidth: 620, minHeight: 480)
                .padding(12)
        }
        .sheet(isPresented: $showEvidence) {
            TeatroHostEvidenceSheet(host: evidenceHost,
                                    depth: $evidenceDepth,
                                    items: evidenceItems,
                                    ask: { Task { await askFromEvidence(host: evidenceHost) } },
                                    copy: { copyToClipboard(evidenceItems.map { $0.text + " — [\($0.title)](\($0.url))" }.joined(separator: "\n")) },
                                    openMap: {
                                        Task {
                                            if serverClassify, !mapPageId.isEmpty, let v = await controllerHolder.controller.fetchVisualUsingServer(pageId: mapPageId, staleThresholdDays: staleDays, classify: true) {
                                                mapImageURL = v.imageURL
                                                mapCovered = v.covered
                                                mapMissing = v.missing
                                                mapStale = v.stale
                                                mapCoverage = v.coverage
                                                mapOverlays = v.covered + v.missing
                                            } else if let r = await controllerHolder.controller.buildEvidenceMapWithStale(host: evidenceHost, staleThresholdDays: staleDays) {
                                                mapPageId = r.pageId
                                                mapImageURL = r.imageURL
                                                mapCovered = r.covered
                                                mapMissing = r.missing
                                                mapStale = r.stale
                                                mapCoverage = r.coverage
                                                mapOverlays = r.covered + r.missing
                                            } else {
                                                mapPageId = ""
                                                mapImageURL = nil
                                                mapCovered = []
                                                mapMissing = []
                                                mapStale = []
                                                mapOverlays = buildMockOverlays(from: evidenceItems)
                                                mapCoverage = Double(VisualCoverageUtils.unionAreaNormalized(mapOverlays.map { $0.rect }))
                                            }
                                            showMap = true
                                        }
                                    },
                                    close: { showEvidence = false })
                .frame(minWidth: 640, minHeight: 420)
                .padding(12)
        }
        .sheet(isPresented: $showMap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Stale Threshold:")
                    Picker("Stale", selection: $staleDays) { Text("30d").tag(30); Text("60d").tag(60); Text("90d").tag(90) }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    Spacer()
                    Toggle("Server Covered", isOn: $serverClassify).toggleStyle(.switch)
                    Button("Reindex Region") {
                        Task {
                            guard !mapPageId.isEmpty, let sel = selectedRect else { return }
                            let ok = await controllerHolder.controller.reindexRegion(pageId: mapPageId, rect: sel)
                            if ok, let r = await controllerHolder.controller.buildEvidenceMapWithStale(host: evidenceHost, staleThresholdDays: staleDays) {
                                mapPageId = r.pageId
                                mapImageURL = r.imageURL
                                mapCovered = r.covered
                                mapMissing = r.missing
                                mapStale = r.stale
                                mapCoverage = r.coverage
                                mapOverlays = r.covered + r.missing
                            }
                        }
                    }.disabled(mapPageId.isEmpty || selectedRect == nil)
                    Button("Refresh Stale") {
                        Task {
                            guard !mapPageId.isEmpty, let stale = await controllerHolder.controller.fetchStaleOverlays(pageId: mapPageId, staleThresholdDays: staleDays) else { return }
                            mapStale = stale
                        }
                    }
                }
                // Compact banner with counts and coverage
                let coveredCount = mapCovered.count
                let missingCount = mapMissing.count
                let staleCount = mapStale.count
                HStack(spacing: 16) {
                    Text("Covered: \(coveredCount)").foregroundStyle(.green)
                    Text("Missing: \(missingCount)").foregroundStyle(.red)
                    Text("Stale: \(staleCount)").foregroundStyle(.orange)
                    Spacer()
                    Text(String(format: "Coverage %.0f%%", mapCoverage * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                EvidenceMapView(
                    title: "Visual Evidence — \(evidenceHost)",
                    imageURL: mapImageURL,
                    covered: mapCovered,
                    stale: mapStale,
                    missing: mapMissing,
                    initialCoverage: mapCoverage,
                    onSelect: { ov in selectedRect = ov.rect; copyToClipboard(ov.id) }
                )
            }
                .frame(minWidth: 720, minHeight: 520)
                .padding(12)
        }
    }

    private func testConnection() async {
        switch await controllerHolder.controller.testConnection() {
        case .ok(let host):
            connectionStatus = "Connected: \(host)"
        case .fail(let message):
            connectionStatus = "Connection failed: \(message)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            connectionStatus = ""
        }
    }
    private func openBaselines() async {
        baselines = await controllerHolder.controller.loadBaselines(limit: 200)
        showBaselines = true
    }
    private func openDrifts() async {
        drifts = await controllerHolder.controller.loadDrifts(limit: 200)
        showDrifts = true
    }
    private func openPatterns() async {
        patterns = await controllerHolder.controller.loadPatterns(limit: 200)
        showPatterns = true
    }
    private func openBuildBaseline() async {
        hosts = await controllerHolder.controller.listHosts()
        selectedHost = hosts.first ?? ""
        buildLevel = 2
        buildStatus = hosts.isEmpty ? "No hosts in corpus. Ingest pages first or include a URL in your question." : ""
        showBuildBaseline = true
    }
    private func openHosts() async {
        hostsCoverage = await controllerHolder.controller.loadHostCoverage(limitPerHost: 6)
        showHosts = true
    }
    private func refreshTopHosts() async {
        let cov = await controllerHolder.controller.loadHostCoverage(limitPerHost: 3)
        topHosts = Array(cov.prefix(3))
    }
    private func openEvidence(host: String) async {
        evidenceHost = host
        evidenceDepth = controllerHolder.controller.config.depthLevel
        evidenceItems = await controllerHolder.controller.evidencePreview(host: host, depthLevel: evidenceDepth)
        showEvidence = true
    }
    private func askFromEvidence(host: String) async {
        controllerHolder.controller.setStrictMemoryMode(true)
        controllerHolder.controller.newChat()
        let prompt = "Summarize \(host) based on our stored snapshot. Provide concise sections with cited bullets."
        controllerHolder.controller.send(prompt)
        showEvidence = false
    }
    private func buildMockOverlays(from items: [(title: String, url: String, text: String)]) -> [EvidenceMapView.Overlay] {
        let n = max(1, min(items.count, 12))
        let cols = n <= 4 ? 2 : 3
        let rows = Int(ceil(Double(n) / Double(cols)))
        var out: [EvidenceMapView.Overlay] = []
        let pad: CGFloat = 0.02
        let cellW: CGFloat = (1.0 - pad * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH: CGFloat = (1.0 - pad * CGFloat(rows + 1)) / CGFloat(rows)
        for i in 0..<n {
            let r = i / cols
            let c = i % cols
            let x = pad + CGFloat(c) * (cellW + pad)
            let y = pad + CGFloat(r) * (cellH + pad)
            let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
            out.append(.init(id: "ov-\(i)", rect: rect, color: .green))
        }
        return out
    }

    private func testLiveChat() async {
        connectionStatus = "Running live test…"
        switch await controllerHolder.controller.testLiveChatRoundtrip() {
        case .ok(let preview):
            connectionStatus = "OpenAI chat ok: \(preview)"
        case .fail(let message):
            connectionStatus = "Live test failed: \(message)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            connectionStatus = ""
        }
    }

    // MARK: - Ingestion
    private func indexURL() async {
        addURLStatus = "Indexing…"
        guard let url = URL(string: addURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else { addURLStatus = "Invalid URL"; return }
        let ok = await controllerHolder.controller.learnSite(url: url, modeLabel: addURLMode, depth: addURLDepth, maxPages: addURLMaxPages)
        addURLStatus = ok ? "Indexed" : "Failed to index"
        if ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                showAddURLSheet = false
                addURLStatus = ""
                addURLString = ""
                addURLDepth = 0
                addURLMaxPages = 12
            }
        }
    }

    private func importFiles() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { _ = await controllerHolder.controller.ingestFiles(urls) }
        }
        #endif
    }
}

private struct TeatroBaselinesSheet: View {
    let items: [MemChatController.BaselineItem]
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Baselines (\(items.count))").font(.title3).bold()
                Spacer()
                Button("Copy All") { copyToClipboard(items.map { $0.content }.joined(separator: "\n\n")) }
                Button("Close") { dismiss(); onClose() }
            }
            Divider()
            if items.isEmpty {
                Text("No baselines stored.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { b in
                            GroupBox(label: Text(Date(timeIntervalSince1970: b.ts), style: .date)) {
                                Text(b.content).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TeatroDriftsSheet: View {
    let items: [MemChatController.DriftItem]
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Drifts (\(items.count))").font(.title3).bold()
                Spacer()
                Button("Copy All") { copyToClipboard(items.map { $0.content }.joined(separator: "\n\n")) }
                Button("Close") { dismiss(); onClose() }
            }
            Divider()
            if items.isEmpty {
                Text("No drift records stored.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(items) { b in GroupBox(label: Text(Date(timeIntervalSince1970: b.ts), style: .date)) { Text(b.content).frame(maxWidth: .infinity, alignment: .leading) } } } }
            }
        }
    }
}

private struct TeatroPatternsSheet: View {
    let items: [MemChatController.PatternsItem]
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Patterns (\(items.count))").font(.title3).bold()
                Spacer()
                Button("Copy All") { copyToClipboard(items.map { $0.content }.joined(separator: "\n\n")) }
                Button("Close") { dismiss(); onClose() }
            }
            Divider()
            if items.isEmpty {
                Text("No patterns stored.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(items) { b in GroupBox(label: Text(Date(timeIntervalSince1970: b.ts), style: .date)) { Text(b.content).frame(maxWidth: .infinity, alignment: .leading) } } } }
            }
        }
    }
}

private struct TeatroBuildBaselineSheet: View {
    let hosts: [String]
    @Binding var selectedHost: String
    @Binding var level: Int
    @Binding var status: String
    @Binding var working: Bool
    var onBuild: () -> Void
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Build Baseline").font(.title3).bold(); Spacer(); Button("Close") { dismiss(); onClose() } }
            Divider()
            if hosts.isEmpty {
                Text("No hosts found in this corpus.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Host", selection: $selectedHost) { ForEach(hosts, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden()
                Stepper("Depth: \(level)", value: $level, in: 1...3)
                HStack { Spacer(); Button(working ? "Working…" : "Build") { onBuild() }.disabled(working || selectedHost.isEmpty) }
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

#if canImport(AppKit)
import AppKit
private func copyToClipboard(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
}
#else
private func copyToClipboard(_ s: String) {}
#endif

private struct TeatroHostEvidenceSheet: View {
    let host: String
    @Binding var depth: Int
    let items: [(title: String, url: String, text: String)]
    var ask: () -> Void
    var copy: () -> Void
    var openMap: () -> Void
    var close: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Evidence — \(host)").font(.title3).bold()
                Spacer()
                Stepper("Depth: \(depth)", value: $depth, in: 1...3).frame(width: 160)
                Button("Copy All") { copy() }
                Button("Ask From Evidence") { ask() }
                Button("Open Map") { openMap() }
                Button("Close") { dismiss(); close() }
            }
            Divider()
            if items.isEmpty { Text("No evidence available for this host.").font(.caption).foregroundStyle(.secondary) }
            else {
                ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(Array(items.enumerated()), id: \.offset) { _, it in Text("• \(it.text) — [\(it.title)](\(it.url))").frame(maxWidth: .infinity, alignment: .leading) } } }
            }
        }
    }
}
private struct TeatroHostsSheet: View {
    let controller: MemChatController
    let items: [MemChatController.HostCoverageItem]
    var openEvidence: (String) -> Void = { _ in }
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var depth: Int = 2
    @State private var maxPages: Int = 30
    @State private var status: [String: String] = [:]
    @State private var learnCount: Int = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hosts (\(items.count))").font(.title3).bold()
                Spacer()
                Stepper("Depth: \(depth)", value: $depth, in: 1...3).frame(width: 160)
                Stepper("Max: \(maxPages)", value: $maxPages, in: 10...200).frame(width: 160)
                Stepper("Learn: \(learnCount)", value: $learnCount, in: 1...10).frame(width: 160)
                Button("Close") { dismiss(); onClose() }
            }
            Divider()
            if items.isEmpty { Text("No hosts found in this corpus.").font(.caption).foregroundStyle(.secondary) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { h in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(h.host).font(.headline); Spacer(); Text("pages: \(h.pages) • segments: \(h.segments)").font(.caption).foregroundStyle(.secondary) }
                                if !h.recent.isEmpty {
                                    ForEach(Array(h.recent.prefix(5).enumerated()), id: \.offset) { _, p in
                                        Text("• \(p.title)").font(.caption)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Button("Build Baseline") {
                                        Task {
                                            status[h.host] = "Building…"
                                            let ok = await controller.buildBaselineAndArtifacts(for: h.host, level: depth)
                                            status[h.host] = ok ? "Baseline ✓" : "No evidence"
                                        }
                                    }
                                    Button("Learn +\(learnCount)") {
                                        Task {
                                            status[h.host] = "Learning…"
                                            let n = await controller.learnMoreForHost(host: h.host, count: learnCount, modeLabel: "standard")
                                            status[h.host] = n > 0 ? "Learned \(n)" : "No links"
                                        }
                                    }
                                    Button("Resegment") {
                                        Task {
                                            status[h.host] = "Resegmenting…"
                                            let n = await controller.resegmentThinPages(host: h.host, maxPages: maxPages)
                                            status[h.host] = n > 0 ? "Resegmented \(n)" : "No changes"
                                        }
                                    }
                                    Button("Evidence…") { openEvidence(h.host) }
                                    if let msg = status[h.host], !msg.isEmpty { Text(msg).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                        }
                    }
                }
            }
        }
    }
}
