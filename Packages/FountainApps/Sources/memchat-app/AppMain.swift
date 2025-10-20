import SwiftUI
import AppKit
import MemChatKit
import SecretStore
import LauncherSignature

@main
struct MemChatApp: App {
    @State private var config: MemChatConfiguration
    @StateObject private var controllerHolder: ControllerHolder
    @State private var showSettings = false
    init() {
        verifyLauncherSignature()
        NSApplication.shared.activate(ignoringOtherApps: true)
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
            MemChatRootView(config: $config, controllerHolder: controllerHolder) { showSettings = true }
            .frame(minWidth: 640, minHeight: 480)
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    memoryCorpusId: config.memoryCorpusId,
                    openAIKey: config.openAIAPIKey ?? "",
                    model: config.model,
                    useGateway: config.gatewayURL != nil,
                    gatewayURLString: config.gatewayURL?.absoluteString ?? (ProcessInfo.processInfo.environment["FOUNTAIN_GATEWAY_URL"] ?? "http://127.0.0.1:8010"),
                    controller: controllerHolder.controller
                ) { newCfg in
                    self.config = newCfg
                    controllerHolder.recreate(with: newCfg)
                }
            }
        }
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: MemChatController
    init(initial: MemChatConfiguration) { controller = MemChatController(config: initial) }
    func recreate(with cfg: MemChatConfiguration) { controller = MemChatController(config: cfg) }
}

struct MemChatRootView: View {
    @Binding var config: MemChatConfiguration
    @ObservedObject var controllerHolder: ControllerHolder
    var openSettings: () -> Void
    // Plan/Memory views removed; memory is now automatic and audited in the trail.
    @State private var connectionStatus: String = ""
    @State private var didRunSelfCheck = false
    @State private var corpora: [String] = []
    @State private var showMergeSheet = false
    @State private var showCorpusManager = false
    @State private var showAddURLSheet = false
    @State private var addURLString: String = ""
    @State private var addURLStatus: String = ""
    @State private var addURLDepth: Int = 2
    @State private var addURLMaxPages: Int = 12
    @State private var addURLMode: String = "standard"
    @State private var isLearning: Bool = false
    @State private var learnStart: Date? = nil
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
    @State private var showHelp = false
    @State private var showEvidence = false
    @State private var evidenceHost: String = ""
    @State private var evidenceDepth: Int = 2
    @State private var evidenceItems: [(title: String, url: String, text: String)] = []
    @State private var showMap = false
    @State private var mapOverlays: [EvidenceMapView.Overlay] = []
    @State private var mapImageURL: URL? = nil
    @State private var mapCoverage: Double = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("MemChat").font(.headline)
                Divider().frame(height: 16)
                Text(controllerHolder.controller.corpusTitle ?? config.memoryCorpusId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(controllerHolder.controller.providerLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Add Memory") {
                    Button("Learn Site…") { showAddURLSheet = true }
                    Button("Import Files…") { importFiles() }
                }
                // Plan/Memory controls removed; memory is handled automatically.
                Button("Test") { Task { await testConnection() } }.help("Check provider/gateway connectivity.")
                Button("Live Test") { Task { await testLiveChat() } }.help("Run a one-shot live chat to confirm replies.")
                Button("Baselines") { Task { await openBaselines() } }.help("View stored baselines.")
                Button("Drifts") { Task { await openDrifts() } }.help("View drift records between baselines.")
                Button("Patterns") { Task { await openPatterns() } }.help("View extracted patterns.")
                Button("Build Baseline") { Task { await openBuildBaseline() } }.help("Build a baseline for a chosen host now.")
                Button("Hosts") { Task { await openHosts() } }.help("Coverage per host with quick actions.")
                Button("?") { showHelp = true }.help("Open MemChat help.")
                Button("Settings") { openSettings() }.help("Preferences for model, gateway, deep mode, and evidence depth.")
            }.padding(8)
            if !connectionStatus.isEmpty {
                Text(connectionStatus).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            // Memory trail (audit of background memory operations)
            if !controllerHolder.controller.memoryTrail.isEmpty {
                let lines = controllerHolder.controller.memoryTrail.suffix(4)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2).foregroundStyle(.tertiary)
                    }
                }.padding(.horizontal, 8)
            }

            // Mini host coverage summary (top 3)
            if !topHosts.isEmpty {
                HStack(spacing: 10) {
                    Text("Top hosts:").font(.caption).foregroundStyle(.secondary)
                    ForEach(topHosts.prefix(3)) { h in
                        Button(action: { Task { await openEvidence(host: h.host) } }) {
                            Text("\(h.host) [p:\(h.pages) s:\(h.segments)]")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                        }.buttonStyle(.plain).help("Inspect evidence and ask a cited summary for this host.")
                    }
                    Spacer()
                    Button("Refresh") { Task { await refreshTopHosts() } }.font(.caption).help("Refresh host coverage snapshot.")
                }
                .padding(.horizontal, 8)
            }
            Divider()
            MemChatView(controller: controllerHolder.controller)
        }
        .task {
            // Run a one-shot self-check on first appearance
            if !didRunSelfCheck {
                didRunSelfCheck = true
                await testLiveChat()
            }
            await reloadCorpora()
        }
        // Hide corpus management UI from primary surface; Settings still exposes it if needed.
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
                        ProgressView(value: Double(max(p.visited,1)), total: Double(max(p.target,1)))
                            .controlSize(.small)
                        Text("Visited \(p.visited)/\(p.target) • Pages \(p.pages) • Segments \(p.segs)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if isLearning {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(addURLStatus.isEmpty ? "Indexing…" : addURLStatus).font(.caption).foregroundStyle(.secondary) }
                } else if !addURLStatus.isEmpty {
                    Text(addURLStatus).font(.caption).foregroundStyle(.secondary)
                }
                HStack { Spacer(); Button(isLearning ? "Working…" : "Learn") { Task { await indexURL() } }.disabled(isLearning || addURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .padding(12)
            .frame(minWidth: 460)
            .onReceive(controllerHolder.controller.$memoryTrail) { lines in
                guard isLearning else { return }
                if let m = lines.last(where: { $0.contains("learn:") || $0.contains("learn complete") || $0.contains("error") }) {
                    addURLStatus = m
                }
            }
        }
        .sheet(isPresented: $showBaselines) {
            BaselinesSheet(items: baselines) { showBaselines = false }
            .frame(minWidth: 560, minHeight: 420)
            .padding(12)
        }
        .sheet(isPresented: $showDrifts) {
            DriftsSheet(items: drifts) { showDrifts = false }
                .frame(minWidth: 560, minHeight: 420)
                .padding(12)
        }
        .sheet(isPresented: $showPatterns) {
            PatternsSheet(items: patterns) { showPatterns = false }
                .frame(minWidth: 560, minHeight: 420)
                .padding(12)
        }
        .sheet(isPresented: $showBuildBaseline) {
            BuildBaselineSheet(hosts: hosts,
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
            HostsSheet(controller: controllerHolder.controller, items: hostsCoverage) { showHosts = false }
                .frame(minWidth: 620, minHeight: 480)
                .padding(12)
        }
        .sheet(isPresented: $showEvidence) {
            HostEvidenceSheet(host: evidenceHost,
                              depth: $evidenceDepth,
                              items: evidenceItems,
                              ask: { Task { await askFromEvidence(host: evidenceHost) } },
                              copy: { copyToClipboard(evidenceItems.map { $0.text + " — [\($0.title)](\($0.url))" }.joined(separator: "\n")) },
                              openMap: {
                                  Task {
                                      if let result = await controllerHolder.controller.buildEvidenceMap(host: evidenceHost) {
                                          mapImageURL = result.imageURL
                                          mapOverlays = result.overlays
                                          mapCoverage = result.coverage
                                      } else {
                                          mapImageURL = nil
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
            EvidenceMapView(title: "Visual Evidence — \(evidenceHost)", imageURL: mapImageURL, covered: mapOverlays, initialCoverage: mapCoverage)
                .frame(minWidth: 720, minHeight: 520)
                .padding(12)
        }
        .sheet(isPresented: $showHelp) { HelpSheet(onClose: { showHelp = false }, openStore: { openStoreFolder() }, openLogs: { openLogsFolder() }) .frame(minWidth: 640, minHeight: 520).padding(12) }
        .task { await refreshTopHosts() }
    }
    private func reloadCorpora() async { corpora = await controllerHolder.controller.listCorpora().sorted() }
    private func createNewCorpus() async {
        let ts = Int(Date().timeIntervalSince1970)
        let newId = "memchat-\(ts)"
        if await controllerHolder.controller.createCorpus(id: newId) {
            switchCorpus(to: newId)
            await reloadCorpora()
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
        // Arrange items into a simple grid of normalized rectangles
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
    private func switchCorpus(to id: String) {
        guard !id.isEmpty, id != config.memoryCorpusId else { return }
        let newCfg = MemChatConfiguration(
            memoryCorpusId: id,
            model: config.model,
            openAIAPIKey: config.openAIAPIKey,
            openAIEndpoint: config.openAIEndpoint,
            localCompatibleEndpoint: config.localCompatibleEndpoint,
            gatewayURL: config.gatewayURL,
            awarenessURL: config.awarenessURL,
            bootstrapURL: config.bootstrapURL
        )
        self.config = newCfg
        controllerHolder.recreate(with: newCfg)
    }
    private func testConnection() async {
        switch await controllerHolder.controller.testConnection() {
        case .ok(let host): connectionStatus = "Connected: \(host)";
        case .fail(let msg): connectionStatus = "Connection failed: \(msg)";
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { connectionStatus = "" }
    }
    private func testLiveChat() async {
        connectionStatus = "Running live test…"
        switch await controllerHolder.controller.testLiveChatRoundtrip() {
        case .ok(let preview): connectionStatus = "OpenAI chat ok: \(preview)";
        case .fail(let msg): connectionStatus = "Live test failed: \(msg)";
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { connectionStatus = "" }
    }

    // MARK: - Ingestion
    private func indexURL() async {
        guard let url = URL(string: addURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else { addURLStatus = "Invalid URL"; return }
        isLearning = true
        learnStart = Date()
        addURLStatus = "Starting…"
        // Timeout notifier (does not cancel crawl; just updates UI)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if isLearning { addURLStatus = "Taking longer than expected… still working" }
        }
        let ok = await controllerHolder.controller.learnSite(url: url, modeLabel: addURLMode, depth: addURLDepth, maxPages: addURLMaxPages)
        isLearning = false
        if ok {
            addURLStatus = "Indexed ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                showAddURLSheet = false
                addURLStatus = ""
                addURLString = ""
                addURLDepth = 2
                addURLMaxPages = 12
            }
        } else {
            addURLStatus = addURLStatus.isEmpty ? "Failed to index (see Memory Trail for details)" : addURLStatus
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

private struct BaselinesSheet: View {
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

private struct DriftsSheet: View {
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

private struct PatternsSheet: View {
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

private struct BuildBaselineSheet: View {
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
private func copyToClipboard(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
}
#else
private func copyToClipboard(_ s: String) {}
#endif

private struct MergeSheet: View {
    let corpora: [String]
    let controller: MemChatController
    var onMerged: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var targetId: String = ""
    @State private var status: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Merge Corpora to New").font(.title3).bold(); Spacer(); Button("Close") { dismiss() } }
            Divider()
            HStack {
                Text("Target Corpus ID").frame(width: 140, alignment: .leading)
                TextField("merged-<timestamp>", text: $targetId).textFieldStyle(.roundedBorder)
                Button("Suggest") { targetId = "merged-\(Int(Date().timeIntervalSince1970))" }
            }
            Text("Select sources:").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(corpora, id: \.self) { c in
                        Toggle(isOn: Binding(
                            get: { selected.contains(c) },
                            set: { isOn in if isOn { _ = selected.insert(c) } else { _ = selected.remove(c) } }
                        )) { Text(c) }
                    }
                }
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Merge") { Task { await performMerge() } }.disabled(selected.isEmpty || targetId.isEmpty) }
        }
        .onAppear { if targetId.isEmpty { targetId = "merged-\(Int(Date().timeIntervalSince1970))" } }
        .frame(minWidth: 520, minHeight: 420)
        .padding(12)
    }
    private func performMerge() async {
        status = "Merging…"
        do {
            try await controller.mergeCorpora(sources: Array(selected), into: targetId)
            status = "Merged into \(targetId)"
            onMerged(targetId)
        } catch {
            status = "Merge failed: \(error.localizedDescription)"
        }
    }
}

private struct CorpusManagerSheet: View {
    let initialCorpusId: String
    let controller: MemChatController
    var onSwitch: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var corpora: [String] = []
    @State private var selected: String = ""
    @State private var status: String = ""
    @State private var newId: String = ""
    @State private var mergeSelected: Set<String> = []
    @State private var mergeTargetId: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Corpus Manager").font(.title3).bold(); Spacer(); Button("Close") { dismiss() } }
            Divider()
            GroupBox(label: Text("Switch Corpus")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Active Corpus", selection: $selected) {
                        ForEach(corpora, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    HStack { Spacer(); Button("Switch") { if !selected.isEmpty { onSwitch(selected); dismiss() } } }
                }
                .padding(8)
            }
            GroupBox(label: Text("Create New")) {
                HStack(spacing: 8) {
                    TextField("memchat-<timestamp>", text: $newId).textFieldStyle(.roundedBorder)
                    Button("Suggest") { newId = "memchat-\(Int(Date().timeIntervalSince1970))" }
                    Button("Create & Switch") { Task { await createAndSwitch() } }.disabled(newId.isEmpty)
                }
                .padding(8)
            }
            GroupBox(label: Text("Merge Corpora → New")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Target ID").frame(width: 80, alignment: .leading)
                        TextField("merged-<timestamp>", text: $mergeTargetId).textFieldStyle(.roundedBorder)
                        Button("Suggest") { mergeTargetId = "merged-\(Int(Date().timeIntervalSince1970))" }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(corpora.filter { $0 != selected }, id: \.self) { c in
                                Toggle(isOn: Binding(
                                    get: { mergeSelected.contains(c) },
                                    set: { on in if on { _ = mergeSelected.insert(c) } else { _ = mergeSelected.remove(c) } }
                                )) { Text(c) }
                            }
                        }
                    }
                    HStack { Spacer(); Button("Merge & Switch") { Task { await performMerge() } }.disabled(mergeSelected.isEmpty || mergeTargetId.isEmpty) }
                }
                .padding(8)
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(minWidth: 640, minHeight: 520)
        .padding(12)
        .task { await load() }
    }
    private func load() async {
        corpora = await controller.listCorpora().sorted()
        selected = initialCorpusId
        if newId.isEmpty { newId = "memchat-\(Int(Date().timeIntervalSince1970))" }
        if mergeTargetId.isEmpty { mergeTargetId = "merged-\(Int(Date().timeIntervalSince1970))" }
    }
    private func createAndSwitch() async {
        status = "Creating corpus…"
        if await controller.createCorpus(id: newId) { onSwitch(newId); dismiss() } else { status = "Create failed" }
    }
    private func performMerge() async {
        status = "Merging…"
        do {
            try await controller.mergeCorpora(sources: Array(mergeSelected), into: mergeTargetId)
            status = "Merged into \(mergeTargetId)"
            onSwitch(mergeTargetId)
            dismiss()
        } catch { status = "Merge failed: \(error.localizedDescription)" }
    }
}
#if canImport(AppKit)
private func openURL(_ s: String) {
    if let u = URL(string: s) { NSWorkspace.shared.open(u) }
}
#else
private func openURL(_ s: String) {}
#endif

private struct HostsSheet: View {
    let controller: MemChatController
    let items: [MemChatController.HostCoverageItem]
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
            if items.isEmpty {
                Text("No hosts found in this corpus.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { h in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(h.host).font(.headline); Spacer(); Text("pages: \(h.pages) • segments: \(h.segments)").font(.caption).foregroundStyle(.secondary) }
                                if !h.recent.isEmpty {
                                    ForEach(Array(h.recent.prefix(5).enumerated()), id: \.offset) { _, p in
                                        Button(action: { openURL(p.url) }) { Text("• \(p.title)").font(.caption) }.buttonStyle(.plain)
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
private struct HostEvidenceSheet: View {
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                            Text("• \(it.text) — [\(it.title)](\(it.url))").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

private struct HelpSheet: View {
    var onClose: () -> Void
    var openStore: () -> Void
    var openLogs: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("MemChat Help").font(.title3).bold(); Spacer(); Button("Close") { dismiss(); onClose() } }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    GroupBox(label: Text("Deep Answer Mode")) {
                        Text("Builds a FactPack (evidence, baselines, drift, patterns, continuity) and composes strictly with citations.")
                    }
                    GroupBox(label: Text("Evidence Depth")) {
                        Text("Controls how many evidence lines we include (1=~8, 2=~16, 3=~32). Higher depth yields more citations and detail.")
                    }
                    GroupBox(label: Text("Strict Memory Mode")) {
                        Text("Answers strictly from the stored memory corpus. If a fact isn’t present, the assistant says so.")
                    }
                    GroupBox(label: Text("Hosts Dashboard")) {
                        Text("Shows per‑host coverage with quick actions: Learn +N, Build Baseline, Resegment. Use it to grow coverage and synthesize artifacts.")
                    }
                    GroupBox(label: Text("Ask From Evidence")) {
                        Text("One‑click cited summary flow. Sets Strict+Deep, builds a FactPack, and streams a structured answer with citations.")
                    }
                    GroupBox(label: Text("Files & Logs")) {
                        HStack(spacing: 12) {
                            Button("Open Store Folder") { openStore() }
                            Button("Open Logs Folder") { openLogs() }
                        }
                        Text("The store folder contains corpora and artifacts; logs folder contains development logs when using local services.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#if canImport(AppKit)
private func openFolderURL(_ url: URL) { NSWorkspace.shared.open(url) }
private func computeStoreURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    if let raw = (env["FOUNTAINSTORE_DIR"] ?? env["ENGRAVER_STORE_PATH"])?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
        if raw.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let suffix = raw.dropFirst()
            return home.appendingPathComponent(String(suffix), isDirectory: true)
        } else {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".fountain", isDirectory: true).appendingPathComponent("engraver-store", isDirectory: true)
}
private func computeLogsURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".fountain", isDirectory: true).appendingPathComponent("logs", isDirectory: true)
}
private func openStoreFolder() { openFolderURL(computeStoreURL()) }
private func openLogsFolder() { openFolderURL(computeLogsURL()) }
#else
private func openStoreFolder() {}
private func openLogsFolder() {}
#endif
