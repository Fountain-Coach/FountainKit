import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct LLMAdapterSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        // Default corpus: baseline-patchbay (so Flow graph in baseline can find it)
        let corpusId = env["CORPUS_ID"] ?? "baseline-patchbay"
        let store: FountainStoreClient = {
            if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
                let url: URL
                if dir.hasPrefix("~") { url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true) }
                else { url = URL(fileURLWithPath: dir, isDirectory: true) }
                if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
            }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()

        do { _ = try await store.createCorpus(corpusId, metadata: ["app": "baseline-patchbay", "kind": "teatro+mrts"]) } catch { }

        let pageId = "prompt:llm-adapter"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://prompt/llm-adapter", host: "store", title: "LLM Adapter — OpenAI-Compatible (Creation)")
        _ = try? await store.addPage(page)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: creationPrompt))

        let mrtsId = "prompt:llm-adapter-mrts"
        let mrtsPage = Page(corpusId: corpusId, pageId: mrtsId, url: "store://prompt/llm-adapter-mrts", host: "store", title: "LLM Adapter — MRTS")
        _ = try? await store.addPage(mrtsPage)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(mrtsId):teatro", pageId: mrtsId, kind: "teatro.prompt", text: mrtsPrompt))
        if let facts = factsJSON() { _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: facts)) }

        print("Seeded LLM Adapter prompts → corpus=\(corpusId) pages=[\(pageId), \(mrtsId)]")
    }

    static let creationPrompt = """
    Scene: LLM Adapter — OpenAI-Compatible (Instrument)
    Text:
    - Identity: { manufacturer: Fountain, product: LLMAdapter, displayName: "LLM Adapter", instanceId: "llm-1" }.
    - Role: Bridge to any LLM compatible with the OpenAI chat + function calling schema. Maps to llm-gateway OpenAPI (`openapi/v1/llm-gateway.yml`), or runs in mock mode for tests.
    - OpenAPI mapping: POST /chat (ChatRequest → ChatResponse) with optional SSE stream.
    - Configuration:
      • llm.provider ("openai" default), llm.model (e.g., "gpt-4o-mini"), gateway.url (llm-gateway base URL), auth via X-API-Key.
      • Secrets never persisted; read API key from Keychain or `LLM_GATEWAY_API_KEY` env when driving remotely.
    - Property Exchange (PE):
      • llm.provider (string), llm.model (string), llm.temperature (float?), gateway.url (string), streaming.enabled (0/1)
      • last.answer (string; R/O), last.function.name (string; R/O), tokens.total (int; R/O), last.ts (ISO8601; R/O)
    - Vendor JSON (SysEx7 UMP):
      • llm.set { provider?, model?, temperature?, gatewayUrl?, streaming? }
      • llm.chat { messages:[{role,content}], functions?:[{name,description?}], function_call?:"auto"|{name} }
      • llm.tool.result { name, result:any } — feed tool output back (future)
    - Flow Ports (typed wiring):
      • inputs: prompt.in (kind:text), messages.in (kind:json), tool.result.in (kind:json)
      • outputs: answer.out (kind:text), function.call.out (kind:json)
    - Monitor/CI Events:
      • "llm.chat.started" { provider, model }
      • "llm.chat.delta" { token } (streaming only)
      • "llm.function_call" { name }
      • "llm.chat.completed" { answer.chars, provider, model }
    """

    static let mrtsPrompt = """
    Scene: LLM Adapter — MRTS
    Text:
    - Objective: Drive llm.chat in mock mode and assert deterministic monitor events and PE snapshot.
    - Steps:
      1) PE SET llm.provider="openai", llm.model="gpt-4o-mini", streaming.enabled=0
      2) Send llm.chat with messages=[{role:"user", content:"Hello"}]
      3) Expect monitor: llm.chat.started → llm.chat.completed; PE.last.answer present and answer.chars>0
      4) Function call path: llm.chat with content:"CALL:sum(1,2)"; expect llm.function_call {name:"sum"}
    - Invariants: completion under 300ms in mock; answer non-empty; function_call triggers on CALL: prefix.
    """

    static func factsJSON() -> String? {
        let facts: [String: Any] = [
            "instrument": [
                "displayName": "LLM Adapter",
                "product": "LLMAdapter",
                "pe": ["llm.provider","llm.model","llm.temperature","gateway.url","streaming.enabled","last.answer","last.function.name","tokens.total","last.ts"],
                "vendorJSON": ["llm.set","llm.chat","llm.tool.result"],
                "ports": [
                    "inputs": [["id": "prompt.in", "kind": "text"], ["id": "messages.in", "kind": "json"], ["id": "tool.result.in", "kind": "json"]],
                    "outputs": [["id": "answer.out", "kind": "text"], ["id": "function.call.out", "kind": "json"]]
                ],
                "openapi": ["v1/llm-gateway.yml /chat"]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]), let s = String(data: data, encoding: .utf8) { return s }
        return nil
    }
}

