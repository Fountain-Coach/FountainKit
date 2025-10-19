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
}
