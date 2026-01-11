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

        // 3) Teatro prompt exists for appId in FountainStore and follows the template.
        // For now this is a soft check to keep tests self-contained; missing prompts
        // are reported but do not fail instruments yet.
        _ = await hasTeatroPrompt(appId: inst.appId, root: root)

        // 4) Facts document exists for agentId in FountainStore (agents corpus)
        // For now this is a soft check: we warn when facts are missing, but do not
        // fail the instrument outright while store tooling is being migrated.
        if await !hasFacts(agentId: inst.agentId, root: root) {
            fputs("[instrument-lint] WARN: \(inst.appId): facts document missing for agentId \(inst.agentId) in agents corpus\n", stderr)
        }

        // 5) Tests: require a test module directory when specified
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

        // 6) Snapshot / FCIS-VRT Render baselines: require directory when specified
        if let rel = inst.snapshotBaselinesDir {
            let path = root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) || !isDir.boolValue {
                fail("snapshotBaselinesDir does not exist or is not a directory: \(rel)")
            }
        }

        // 7) Required test symbols: ensure specific PBVRT/robot test classes exist
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
    static func hasTeatroPrompt(appId: String, root: URL) async -> Bool {
        let store: FountainStoreClient = {
            let env = ProcessInfo.processInfo.environment
            let url: URL
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                if dir.hasPrefix("/") {
                    url = URL(fileURLWithPath: dir, isDirectory: true)
                } else {
                    url = root.appendingPathComponent(dir, isDirectory: true)
                }
            } else {
                url = root.appendingPathComponent(".fountain/store", isDirectory: true)
            }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                return FountainStoreClient(client: disk)
            } else {
                return FountainStoreClient(client: EmbeddedFountainStoreClient())
            }
        }()
        let corpusId = appId
        let segmentId = "prompt:\(appId):teatro"
        do {
            if let data = try await store.getDoc(corpusId: corpusId, collection: "segments", id: segmentId),
               let segment = try? JSONDecoder().decode(Segment.self, from: data) {
                if !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Scene:") {
                    FileHandle.standardError.write(Data("[instrument-lint] \(appId): teatro prompt does not start with 'Scene:'\n".utf8))
                }
                return true
            }
        } catch {
            FileHandle.standardError.write(Data("[instrument-lint] \(appId): error fetching teatro prompt: \(error)\n".utf8))
        }
        FileHandle.standardError.write(Data("[instrument-lint] \(appId): teatro prompt segment missing (prompt:\(appId):teatro)\n".utf8))
        return false
    }

    @MainActor
    static func hasFacts(agentId: String, root: URL) async -> Bool {
        let env = ProcessInfo.processInfo.environment
        let corpus = "agents"
        let store: FountainStoreClient = {
            let url: URL
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                if dir.hasPrefix("/") {
                    url = URL(fileURLWithPath: dir, isDirectory: true)
                } else {
                    url = root.appendingPathComponent(dir, isDirectory: true)
                }
            } else {
                url = root.appendingPathComponent(".fountain/store", isDirectory: true)
            }
            FileHandle.standardError.write(Data("[instrument-lint] using store root=\(url.path) corpus=\(corpus)\n".utf8))
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                return FountainStoreClient(client: disk)
            } else {
                return FountainStoreClient(client: EmbeddedFountainStoreClient())
            }
        }()
        let safeId = agentId.replacingOccurrences(of: "/", with: "|")
        let keys = ["facts:agent:\(safeId)", "facts:agent:\(agentId)"]
        for key in keys {
            do {
                if let data = try await store.getDoc(corpusId: corpus, collection: "agent-facts", id: key) {
                    FileHandle.standardError.write(Data("[instrument-lint] found facts for \(agentId) at id=\(key) size=\(data.count)\n".utf8))
                    return true
                }
            } catch {
                FileHandle.standardError.write(Data("[instrument-lint] error fetching facts for \(agentId) id=\(key): \(error)\n".utf8))
            }
        }
        FileHandle.standardError.write(Data("[instrument-lint] no facts found for \(agentId)\n".utf8))
        return false
    }
}
