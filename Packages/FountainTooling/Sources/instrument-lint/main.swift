import Foundation
import FountainStoreClient

@main
struct InstrumentLint {
    struct Instrument: Decodable {
        let appId: String
        let agentId: String
        let corpusId: String
        let spec: String
        let runtimeAgentId: String?
        let testModulePath: String?
        let snapshotBaselinesDir: String?
        let requiredTestSymbols: [String]?
    }

    static func main() async {
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let toolsPath = root.appendingPathComponent("Tools/instruments.json")
            guard let data = try? Data(contentsOf: toolsPath) else {
                fputs("[instrument-lint] WARN: Tools/instruments.json not found — nothing to check\n", stderr)
                return
            }
            let instruments = try JSONDecoder().decode([Instrument].self, from: data)
            if instruments.isEmpty {
                fputs("[instrument-lint] OK: no instruments listed\n", stderr)
                return
            }

            var hadError = false
            for inst in instruments {
                if await !checkInstrument(inst, root: root) {
                    hadError = true
                }
            }
            if hadError {
                exit(1)
            } else {
                fputs("[instrument-lint] ✅ all instruments passed basic checks\n", stderr)
            }
        } catch {
            fputs("[instrument-lint] error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func checkInstrument(_ inst: Instrument, root: URL) async -> Bool {
        var ok = true
        func fail(_ msg: String) {
            ok = false
            fputs("[instrument-lint] \(inst.appId): \(msg)\n", stderr)
        }

        // 1) Spec file exists
        let specPath = root
            .appendingPathComponent("Packages/FountainSpecCuration/openapi/v1/\(inst.spec)")
        if !FileManager.default.fileExists(atPath: specPath.path) {
            fail("spec missing at \(specPath.path)")
        }

        // 2) AgentId appears in openapi-to-facts mapping
        let scriptPath = root.appendingPathComponent("Scripts/openapi/openapi-to-facts.sh")
        if let script = try? String(contentsOf: scriptPath),
           script.contains(inst.agentId) == false {
            fail("agentId \(inst.agentId) is not referenced in Scripts/openapi/openapi-to-facts.sh")
        }

        // 3) Facts document exists for agentId in FountainStore (agents corpus)
        if await !hasFacts(agentId: inst.agentId) {
            fail("facts document missing for agentId \(inst.agentId) in agents corpus")
        }

        // 4) Tests: require a test module directory when specified
        if let rel = inst.testModulePath {
            let path = root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) || !isDir.boolValue {
                fail("testModulePath does not exist or is not a directory: \(rel)")
            } else {
                // Require at least one Swift file as a proxy for test presence
                if (try? FileManager.default.contentsOfDirectory(atPath: path.path))?
                    .contains(where: { $0.hasSuffix(".swift") }) != true {
                    fail("testModulePath \(rel) contains no Swift sources")
                }
            }
        }

        // 5) Snapshot / PB-VRT baselines: require directory when specified
        if let rel = inst.snapshotBaselinesDir {
            let path = root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) || !isDir.boolValue {
                fail("snapshotBaselinesDir does not exist or is not a directory: \(rel)")
            }
        }

        // 6) Required test symbols: ensure specific PBVRT/robot test classes exist
        if let symbols = inst.requiredTestSymbols, !symbols.isEmpty {
            guard let rel = inst.testModulePath else {
                fail("requiredTestSymbols specified but no testModulePath for \(inst.appId)")
                return ok
            }
            let path = root.appendingPathComponent(rel)
            var found: Set<String> = []
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path.path) {
                for file in files where file.hasSuffix(".swift") {
                    let fpath = path.appendingPathComponent(file)
                    if let data = try? Data(contentsOf: fpath),
                       let text = String(data: data, encoding: .utf8) {
                        for sym in symbols where !found.contains(sym) {
                            if text.contains(sym) {
                                found.insert(sym)
                            }
                        }
                    }
                }
            }
            for sym in symbols where !found.contains(sym) {
                fail("required test symbol '\(sym)' not found under \(rel)")
            }
        }

        return ok
    }

    @MainActor
    static func hasFacts(agentId: String) async -> Bool {
        let env = ProcessInfo.processInfo.environment
        let corpus = "agents"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                    return FountainStoreClient(client: disk)
                }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
                return FountainStoreClient(client: disk)
            }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        let safeId = agentId.replacingOccurrences(of: "/", with: "|")
        let keys = ["facts:agent:\(safeId)", "facts:agent:\(agentId)"]
        for key in keys {
            if let _ = try? await store.getDoc(corpusId: corpus, collection: "agent-facts", id: key) {
                return true
            }
        }
        return false
    }
}
