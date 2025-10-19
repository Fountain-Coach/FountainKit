import SwiftUI
import SecretStore
import MemChatKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var memoryCorpusId: String
    @State var openAIKey: String
    @State var model: String
    @State var useGateway: Bool
    @State var gatewayURLString: String
    @State private var showSemanticPanel: Bool = true
    @State private var showSources: Bool = false
    var controller: MemChatController
    var apply: (MemChatConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("MemChat Settings").font(.title3).bold(); Spacer(); Button("Done") { dismiss() } }
            Divider()
            Form {
                LabeledContent("Memory Corpus") {
                    HStack(spacing: 8) {
                        TextField("memchat-app", text: $memoryCorpusId)
                            .textFieldStyle(.roundedBorder)
                        Menu("Choose") { ForEach(corpora, id: \.self) { c in Button(c) { memoryCorpusId = c } } }
                        Button("New") { Task { await createNewCorpus() } }
                        Button("Merge…") { showMerge = true }
                    }
                }
                LabeledContent("Model") { TextField("gpt-4o-mini", text: $model).textFieldStyle(.roundedBorder) }
                LabeledContent("OpenAI API Key") { SecureField("sk-...", text: $openAIKey).textFieldStyle(.roundedBorder) }
                Toggle("Use Gateway", isOn: $useGateway)
                LabeledContent("Gateway URL") { TextField("http://127.0.0.1:8010", text: $gatewayURLString).textFieldStyle(.roundedBorder).disabled(!useGateway) }
                Toggle("Show Semantic Panel", isOn: $showSemanticPanel)
                Toggle("Show Sources", isOn: $showSources)
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Save & Apply") { onSave() }
            }
        }
        .padding(12)
        .frame(minWidth: 520)
        .onAppear {
            loadKeychain()
            self.showSemanticPanel = controller.config.showSemanticPanel
            self.showSources = controller.config.showSources
            Task { await reloadCorpora() }
        }
        .sheet(isPresented: $showMerge) {
            MergeSheet(corpora: corpora.filter { $0 != memoryCorpusId }, controller: controller) { target in
                memoryCorpusId = target
                Task { await reloadCorpora() }
            }
            .frame(minWidth: 520, minHeight: 420)
            .padding(12)
        }
    }

    @State private var corpora: [String] = []
    @State private var showMerge = false

    private func loadKeychain() {
        #if canImport(Security)
        let store = KeychainStore(service: "FountainAI")
        if let data = try? store.retrieveSecret(for: "OPENAI_API_KEY"), let s = String(data: data, encoding: .utf8), !s.isEmpty {
            openAIKey = s
        }
        #endif
    }

    private func reloadCorpora() async {
        corpora = await controller.listCorpora().sorted()
    }

    private func createNewCorpus() async {
        let ts = Int(Date().timeIntervalSince1970)
        let newId = "memchat-\(ts)"
        let ok = await controller.createCorpus(id: newId)
        if ok {
            memoryCorpusId = newId
            await reloadCorpora()
        }
    }

    private func onSave() {
        #if canImport(Security)
        let store = KeychainStore(service: "FountainAI")
        if let data = openAIKey.data(using: .utf8) {
            try? store.storeSecret(data, for: "OPENAI_API_KEY")
        }
        #endif
        let gw = useGateway ? URL(string: gatewayURLString) : nil
        let cfg = MemChatConfiguration(
            memoryCorpusId: memoryCorpusId,
            model: model.isEmpty ? "gpt-4o-mini" : model,
            openAIAPIKey: openAIKey.isEmpty ? nil : openAIKey,
            openAIEndpoint: nil,
            localCompatibleEndpoint: nil,
            gatewayURL: gw,
            awarenessURL: nil,
            showSemanticPanel: showSemanticPanel,
            showSources: showSources
        )
        apply(cfg)
        dismiss()
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
