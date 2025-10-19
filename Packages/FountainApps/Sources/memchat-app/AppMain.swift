import SwiftUI
import AppKit
import MemChatKit
import SecretStore
import LauncherSignature

@main
struct MemChatApp: App {
    @State private var config: MemChatConfiguration
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
        let local = env["ENGRAVER_LOCAL_LLM_URL"] ?? "http://127.0.0.1:11434/v1/chat/completions"
        _config = State(initialValue: MemChatConfiguration(memoryCorpusId: memory, model: "gpt-4o-mini", openAIAPIKey: key, openAIEndpoint: nil, localCompatibleEndpoint: URL(string: local)))
    }
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                HStack {
                    Text("MemChat").font(.headline)
                    Spacer()
                    Button("Settings") { showSettings = true }
                }.padding(8)
                Divider()
                MemChatView(configuration: config)
            }
            .frame(minWidth: 640, minHeight: 480)
            .sheet(isPresented: $showSettings) {
                SettingsView(memoryCorpusId: config.memoryCorpusId, openAIKey: config.openAIAPIKey ?? "", localLLMURL: config.localCompatibleEndpoint?.absoluteString ?? "http://127.0.0.1:11434/v1/chat/completions") { newCfg in
                    self.config = newCfg
                }
            }
        }
    }
}
