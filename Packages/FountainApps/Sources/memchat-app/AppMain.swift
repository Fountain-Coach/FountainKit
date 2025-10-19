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
                    gatewayURLString: config.gatewayURL?.absoluteString ?? (ProcessInfo.processInfo.environment["FOUNTAIN_GATEWAY_URL"] ?? "http://127.0.0.1:8010")
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
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("MemChat").font(.headline)
                Divider().frame(height: 16)
                Text(config.memoryCorpusId).font(.caption).foregroundStyle(.secondary)
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
        }
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
