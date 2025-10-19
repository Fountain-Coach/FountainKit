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
            localCompatibleEndpoint: nil
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
                    gatewayURLString: config.gatewayURL?.absoluteString ?? (ProcessInfo.processInfo.environment["FOUNTAIN_GATEWAY_URL"] ?? "http://127.0.0.1:8010")
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

            MemChatTeatroView(controller: controllerHolder.controller)
        }
        .task {
            if !didRunSelfCheck {
                didRunSelfCheck = true
                await testLiveChat()
            }
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
