import SwiftUI
import AppKit
import MemChatKit
import SecretStore
import LauncherSignature

@main
struct MemChatApp: App {
    @State private var config: MemChatConfiguration
    @StateObject private var controllerHolder = ControllerHolder()
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
        _config = State(initialValue: MemChatConfiguration(memoryCorpusId: memory, model: "gpt-4o-mini", openAIAPIKey: key, openAIEndpoint: nil, localCompatibleEndpoint: nil))
    }
    var body: some Scene {
        WindowGroup {
            MemChatRootView(config: $config, controllerHolder: controllerHolder) { showSettings = true }
            .frame(minWidth: 640, minHeight: 480)
            .sheet(isPresented: $showSettings) {
                SettingsView(memoryCorpusId: config.memoryCorpusId, openAIKey: config.openAIAPIKey ?? "", model: config.model) { newCfg in
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
    init(initial: MemChatConfiguration = MemChatConfiguration(memoryCorpusId: "memchat-app")) {
        controller = MemChatController(config: initial)
    }
    func recreate(with cfg: MemChatConfiguration) { controller = MemChatController(config: cfg) }
}

struct MemChatRootView: View {
    @Binding var config: MemChatConfiguration
    @ObservedObject var controllerHolder: ControllerHolder
    var openSettings: () -> Void
    @State private var showPlan = false
    @State private var planLoading = false
    @State private var planText: String = ""
    @State private var showMemory = false
    @State private var memoryLoading = false
    @State private var pages: [MemChatController.PageItem] = []
    @State private var memoryText: String = ""
    @State private var selectedPage: MemChatController.PageItem?
    @State private var connectionStatus: String = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("MemChat").font(.headline)
                Divider().frame(height: 16)
                Text(config.memoryCorpusId).font(.caption).foregroundStyle(.secondary)
                Text(controllerHolder.controller.providerLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Plan") { Task { await openPlan() } }
                Button("Memory") { Task { await openMemory() } }
                Button("Test") { Task { await testConnection() } }
                Button("Live Test") { Task { await testLiveChat() } }
                Button("Settings") { openSettings() }
            }.padding(8)
            if !connectionStatus.isEmpty {
                Text(connectionStatus).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            Divider()
            MemChatView(controller: controllerHolder.controller)
        }
        .sheet(isPresented: $showPlan) {
            ZStack {
                ScrollView { Text(planText).frame(maxWidth: .infinity, alignment: .leading).padding() }
                if planLoading { ProgressView("Loading plan…").controlSize(.large) }
            }
            .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $showMemory) {
            ZStack {
                HStack(spacing: 0) {
                    List(pages, selection: $selectedPage) { p in Text(p.title).tag(p as MemChatController.PageItem?) }
                        .frame(minWidth: 220)
                    Divider()
                    ScrollView { Text(memoryText).frame(maxWidth: .infinity, alignment: .leading).padding() }
                }
                if memoryLoading { ProgressView("Loading memory…").controlSize(.large) }
            }
            .frame(minWidth: 720, minHeight: 500)
            .onChange(of: selectedPage) { newVal in Task { await loadSelectedPage() } }
        }
    }
    private func openPlan() async { planLoading = true; showPlan = true; defer { planLoading = false }; planText = await controllerHolder.controller.loadPlanText() ?? "(No plan found)" }
    private func openMemory() async { memoryLoading = true; showMemory = true; defer { memoryLoading = false }; pages = await controllerHolder.controller.listMemoryPages(limit: 200); selectedPage = pages.first; await loadSelectedPage() }
    private func loadSelectedPage() async { if let pid = selectedPage?.id { memoryText = await controllerHolder.controller.fetchPageText(pageId: pid) ?? "(No content)" } }
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
