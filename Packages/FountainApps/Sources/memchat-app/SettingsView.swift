import SwiftUI
import SecretStore
import MemChatKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var memoryCorpusId: String
    @State var openAIKey: String
    @State var localLLMURL: String
    var apply: (MemChatConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("MemChat Settings").font(.title3).bold(); Spacer(); Button("Done") { dismiss() } }
            Divider()
            Form {
                LabeledContent("Memory Corpus") { TextField("memchat-app", text: $memoryCorpusId).textFieldStyle(.roundedBorder) }
                LabeledContent("OpenAI API Key") { SecureField("sk-...", text: $openAIKey).textFieldStyle(.roundedBorder) }
                LabeledContent("Local LLM URL") { TextField("http://127.0.0.1:11434/v1/chat/completions", text: $localLLMURL).textFieldStyle(.roundedBorder) }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Save & Apply") { onSave() }
            }
        }
        .padding(12)
        .frame(minWidth: 520)
        .onAppear { loadKeychain() }
    }

    private func loadKeychain() {
        #if canImport(Security)
        let store = KeychainStore(service: "FountainAI")
        if let data = try? store.retrieveSecret(for: "OPENAI_API_KEY"), let s = String(data: data, encoding: .utf8), !s.isEmpty {
            openAIKey = s
        }
        #endif
    }

    private func onSave() {
        #if canImport(Security)
        let store = KeychainStore(service: "FountainAI")
        if let data = openAIKey.data(using: .utf8) {
            try? store.storeSecret(data, for: "OPENAI_API_KEY")
        }
        #endif
        let cfg = MemChatConfiguration(
            memoryCorpusId: memoryCorpusId,
            model: "gpt-4o-mini",
            openAIAPIKey: openAIKey.isEmpty ? nil : openAIKey,
            openAIEndpoint: nil,
            localCompatibleEndpoint: URL(string: localLLMURL),
            gatewayURL: nil,
            awarenessURL: nil
        )
        apply(cfg)
        dismiss()
    }
}

