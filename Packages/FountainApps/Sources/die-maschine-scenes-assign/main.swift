import Foundation
import FountainStoreClient

// Assign instrumentation for Act I/II, Scene 1, refactored toward midi2sampler use (based on default).
// This tool reads prompt:die-maschine:facts, updates scenes, and writes back.

@main
struct DieMaschineScenesAssign {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "die-maschine"
        let store = resolveStore()

        let pageId = "prompt:die-maschine"
        let segId = "\(pageId):facts"

        guard let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId),
              let outer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = outer["text"] as? String,
              let factsData = text.data(using: .utf8),
              var facts = (try? JSONSerialization.jsonObject(with: factsData)) as? [String: Any] else {
            fprint("error: cannot read current facts at \(segId) in corpus=\(corpusId)")
            return
        }

        // Build instrumentation block
        // Derived from YAML Partitur families; channels are tentative and subject to curation.
        let channelPlan: [Int: String] = [
            1: "vl1", 2: "vl2", 3: "vla", 4: "vc", 5: "kb",
            6: "fl", 7: "ob", 8: "cl", 9: "fg",
            10: "perc1",
            11: "hn", 12: "tpt", 13: "tbn",
            14: "elektronik_a", 15: "elektronik_b",
            16: "chor_aa"
        ]
        var channelsArr: [[String: Any]] = []
        for ch in (1...16) {
            if let name = channelPlan[ch] {
                channelsArr.append(["channel": ch, "name": name])
            }
        }
        let instrumentation: [String: Any] = [
            "samplerProfile": "midi2sampler",
            "programBase": "default",
            "mapping": ["channels": channelsArr],
            "notes": "Based on default; refactored for midi2sampler. Subject to curation."
        ]

        // Place Act I mapping under Act 1 / Scene 1 / rehearsals
        // Place Act II mapping under Act 3 / Scene 1 / rehearsals
        if var acts = facts["acts"] as? [[String: Any]] {
            func putRehearsal(actIndex: Int, sceneIndex: Int, title: String, instr: [String: Any]) {
                guard actIndex < acts.count else { return }
                var act = acts[actIndex]
                guard var scenes = act["scenes"] as? [[String: Any]], sceneIndex < scenes.count else { return }
                var scene = scenes[sceneIndex]
                var rehearsals = (scene["rehearsals"] as? [[String: Any]]) ?? []
                let reh: [String: Any] = [
                    "id": "\(actIndex+1)-\(sceneIndex+1)-reh-1",
                    "title": title,
                    "instrumentation": instr
                ]
                // Replace first or append
                if rehearsals.isEmpty { rehearsals = [reh] } else { rehearsals[0] = reh }
                scene["rehearsals"] = rehearsals
                // Remove top-level instrumentation if present
                scene.removeValue(forKey: "instrumentation")
                scenes[sceneIndex] = scene
                act["scenes"] = scenes
                acts[actIndex] = act
            }
            putRehearsal(actIndex: 0, sceneIndex: 0, title: "Rehearsals", instr: instrumentation)
            putRehearsal(actIndex: 2, sceneIndex: 0, title: "Rehearsals", instr: instrumentation)
            facts["acts"] = acts
        }

        // Write back
        guard let outData = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]),
              let outText = String(data: outData, encoding: .utf8) else {
            fprint("error: cannot encode updated facts")
            return
        }
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: segId, pageId: pageId, kind: "facts", text: outText))
        print("Updated instrumentation: Act I → Act1/Scene1/Rehearsals, Act II → Act3/Scene1/Rehearsals in \(segId)")
    }

    static func resolveStore() -> FountainStoreClient {
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
}

func fprint(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
