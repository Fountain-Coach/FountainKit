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
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("MemChat").font(.headline)
                Divider().frame(height: 16)
                // Corpus quick controls
                HStack(spacing: 6) {
                    Text(config.memoryCorpusId).font(.caption).foregroundStyle(.secondary)
                    Menu("Corpus") {
                        if corpora.isEmpty { Button("Reload…") { Task { await reloadCorpora() } } }
                        ForEach(corpora.sorted(), id: \.self) { c in
                            Button("Switch to \(c)") { switchCorpus(to: c) }
                        }
                        Divider()
                        Button("New Corpus") { Task { await createNewCorpus() } }
                        Button("Merge…") { showMergeSheet = true }
                        Button("Reload List") { Task { await reloadCorpora() } }
                    }
                }
                Text(controllerHolder.controller.providerLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Plan/Memory buttons removed; memory is handled automatically.
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
        .sheet(isPresented: $showMergeSheet) {
            MergeSheet(corpora: corpora.filter { $0 != config.memoryCorpusId }, controller: controllerHolder.controller) { target in
                switchCorpus(to: target)
                Task { await reloadCorpora() }
            }
            .frame(minWidth: 520, minHeight: 420)
            .padding(12)
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
