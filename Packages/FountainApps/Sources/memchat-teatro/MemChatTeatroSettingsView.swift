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
    @State var evidenceDepth: Int
    @State private var showSemanticPanel: Bool = true
    @State private var showSources: Bool = false
    @State private var deepAnswerMode: Bool = true
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
                        .help("The corpus to read memory from and persist chat artifacts to.")
                }
                LabeledContent("Model") {
                    TextField("gpt-4o-mini", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .help("Provider model name used for chat calls.")
                }
                LabeledContent("OpenAI API Key") {
                    SecureField("sk-...", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Use Gateway", isOn: $useGateway).help("Route chat calls through the local Gateway (recommended for deep reasoning routes).")
                LabeledContent("Gateway URL") {
                    TextField("http://127.0.0.1:8010", text: $gatewayURLString)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!useGateway)
                        .help("Gateway base URL hosting the /chat endpoint.")
                }
                Toggle("Show Semantic Panel", isOn: $showSemanticPanel).help("Show lightweight context in the UI (sources, stepstones).")
                Toggle("Show Sources", isOn: $showSources).help("Display linked sources where applicable.")
                Toggle("Deep Answer Mode", isOn: $deepAnswerMode).help("Build a FactPack from memory and compose strictly with citations. More grounded; slightly slower.")
                Stepper("Evidence Depth: \(evidenceDepth)", value: $evidenceDepth, in: 1...3).help("How many evidence lines to include in the FactPack (1=~8, 2=~16, 3=~32).")
                Stepper("Evidence Depth: \(evidenceDepth)", value: $evidenceDepth, in: 1...3)
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
            showSources: showSources,
            deepSynthesis: deepAnswerMode,
            depthLevel: evidenceDepth
        )
        apply(cfg)
        dismiss()
    }
}
