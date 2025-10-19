import SwiftUI
import SecretStore
import MemChatKit

struct MemChatTeatroSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var memoryCorpusId: String
    @State var openAIKey: String
    @State var model: String
    @State var useGateway: Bool
    @State var gatewayURLString: String
    @State private var showSemanticPanel: Bool = true
    @State private var showSources: Bool = false
    var apply: (MemChatConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MemChat Teatro Settings").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }
            }
            Divider()
            Form {
                LabeledContent("Memory Corpus") {
                    TextField("memchat-app", text: $memoryCorpusId)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Model") {
                    TextField("gpt-4o-mini", text: $model)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("OpenAI API Key") {
                    SecureField("sk-...", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Use Gateway", isOn: $useGateway)
                LabeledContent("Gateway URL") {
                    TextField("http://127.0.0.1:8010", text: $gatewayURLString)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!useGateway)
                }
                Toggle("Show Semantic Panel", isOn: $showSemanticPanel)
                Toggle("Show Sources", isOn: $showSources)
            }
            .formStyle(.grouped)
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
        if let data = try? store.retrieveSecret(for: "OPENAI_API_KEY"),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            openAIKey = value
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
        let gateway = useGateway ? URL(string: gatewayURLString) : nil
        let cfg = MemChatConfiguration(
            memoryCorpusId: memoryCorpusId,
            model: model.isEmpty ? "gpt-4o-mini" : model,
            openAIAPIKey: openAIKey.isEmpty ? nil : openAIKey,
            openAIEndpoint: nil,
            localCompatibleEndpoint: nil,
            gatewayURL: gateway,
            awarenessURL: nil,
            showSemanticPanel: showSemanticPanel,
            showSources: showSources
        )
        apply(cfg)
        dismiss()
    }
}
