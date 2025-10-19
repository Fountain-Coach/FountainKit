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
        let initial = MemChatConfiguration(memoryCorpusId: memory, model: "gpt-4o-mini", openAIAPIKey: key, openAIEndpoint: nil, localCompatibleEndpoint: nil)
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
                Button("Test") { Task { await testConnection() } }
                Button("Live Test") { Task { await testLiveChat() } }
                Button("Settings") { openSettings() }
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
