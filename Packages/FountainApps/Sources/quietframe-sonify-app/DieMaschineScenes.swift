import SwiftUI
import FountainStoreClient

struct ActsScenesView: View {
    @State private var model = ActsModel()
    @State private var selectedAct: Int? = 0
    @State private var selectedScene: Int? = 0
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedAct) {
                ForEach(model.acts.indices, id: \.self) { idx in
                    Text(model.acts[idx].title)
                }
            }
            .navigationTitle("Acts")
        } content: {
            if let actIdx = selectedAct, actIdx < model.acts.count {
                List(selection: $selectedScene) {
                    ForEach(model.acts[actIdx].scenes.indices, id: \.self) { sidx in
                        Text(model.acts[actIdx].scenes[sidx].title)
                    }
                }
                .navigationTitle(model.acts[actIdx].title)
            } else { Text("Select an Act") }
        } detail: {
            if let actIdx = selectedAct, let sidx = selectedScene,
               actIdx < model.acts.count, sidx < model.acts[actIdx].scenes.count {
                SceneDetailView(scene: model.acts[actIdx].scenes[sidx])
            } else {
                VStack { Text("Select a Scene").foregroundStyle(.secondary) }
            }
        }
        .task {
            var m = model
            await m.load()
            model = m
        }
    }
}

struct SceneDetailView: View {
    let scene: SceneModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scene.title).font(.title3)
            if let instr = scene.instrumentation {
                Text("Sampler: \(instr.samplerProfile) (base=\(instr.programBase))").font(.caption).foregroundStyle(.secondary)
                Table(instr.channels) {
                    TableColumn("Ch") { ch in Text("\(ch.channel)").monospaced() }
                    TableColumn("Name") { ch in Text(ch.name) }
                }
                .frame(minHeight: 200)
                if !instr.notes.isEmpty { Text(instr.notes).font(.caption2).foregroundStyle(.secondary) }
            } else {
                Text("No instrumentation assigned").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Model
struct ActsModel {
    var acts: [ActModel] = []
    mutating func loadFromFacts(_ facts: [String: Any]) {
        var out: [ActModel] = []
        if let arr = facts["acts"] as? [[String: Any]] {
            for a in arr {
                let title = (a["title"] as? String) ?? "Act"
                var scenes: [SceneModel] = []
                if let sc = a["scenes"] as? [[String: Any]] {
                    for s in sc {
                        let stitle = (s["title"] as? String) ?? "Scene"
                        var inst: Instrumentation? = nil
                        if let instr = s["instrumentation"] as? [String: Any] {
                            let profile = (instr["samplerProfile"] as? String) ?? ""
                            let base = (instr["programBase"] as? String) ?? ""
                            let notes = (instr["notes"] as? String) ?? ""
                            var channels: [ChannelMap] = []
                            if let mapping = instr["mapping"] as? [String: Any], let chans = mapping["channels"] as? [[String: Any]] {
                                for c in chans {
                                    if let ch = c["channel"] as? Int, let name = c["name"] as? String {
                                        channels.append(ChannelMap(channel: ch, name: name))
                                    }
                                }
                            }
                            inst = Instrumentation(samplerProfile: profile, programBase: base, notes: notes, channels: channels)
                        }
                        scenes.append(SceneModel(title: stitle, instrumentation: inst))
                    }
                }
                out.append(ActModel(title: title, scenes: scenes))
            }
        }
        self.acts = out
    }

    mutating func load() async {
        let store = resolveStore()
        let corpusId = ProcessInfo.processInfo.environment["CORPUS_ID"] ?? "die-maschine"
        let segId = "prompt:die-maschine:facts"
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId),
           let s = String(data: data, encoding: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
           let text = obj["text"] as? String,
           let tdata = text.data(using: .utf8),
           let facts = try? JSONSerialization.jsonObject(with: tdata) as? [String: Any] {
            loadFromFacts(facts)
        } else {
            self.acts = []
        }
    }
}

struct ActModel { var title: String; var scenes: [SceneModel] }
struct SceneModel { var title: String; var instrumentation: Instrumentation? }
struct Instrumentation { var samplerProfile: String; var programBase: String; var notes: String; var channels: [ChannelMap] }
struct ChannelMap: Identifiable { var id: Int { channel }; var channel: Int; var name: String }

func resolveStore() -> FountainStoreClient {
    let env = ProcessInfo.processInfo.environment
    if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
        let url: URL
        if dir.hasPrefix("~") {
            url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
        } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
        if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
        return FountainStoreClient(client: disk)
    }
    return FountainStoreClient(client: EmbeddedFountainStoreClient())
}

