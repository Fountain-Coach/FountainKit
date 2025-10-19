import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct MemChatConceptSeed {
    static func main() async {
        verifyLauncherSignature()

        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "memchat-app"
        let store = resolveStore()

        // Ensure corpus exists
        do { try await store.createCorpus(corpusId) } catch { /* ignore */ }

        // Create the concept plan page and segment
        let pageId = "plan:memchat-concept"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://plan/memchat", host: "store", title: "MemChat — Concept & Plan")
        _ = try? await store.addPage(page)

        let plan = conceptPlan(corpusId: corpusId)
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):plan", pageId: pageId, kind: "plan", text: plan))

        // Seed a baseline capturing the initial plan
        let baselineObj: [String: Any] = [
            "kind": "project-baseline",
            "pages": [pageId],
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: baselineObj), let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addBaseline(.init(corpusId: corpusId, baselineId: "baseline-initial", content: json))
        }

        print("memchat concept seeded • corpusId=\(corpusId) pageId=\(pageId)")
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                return FountainStoreClient(client: disk)
            }
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

    static func conceptPlan(corpusId: String) -> String {
        return """
        MemChat — A Discreet, Context‑Aware Chat App

        1) Product Concept
        MemChat is a minimal, high‑signal chat app that silently augments every turn with relevant memory from a user’s working corpus while persisting each conversation in its own isolated chat corpus. The user stays focused on their own thoughts; the model discretely consults their corpus to stay grounded and helpful. Transparency is on‑demand (trace), never intrusive.

        2) Goals
        - Discreet assistance: No chain‑of‑thought or noisy UI; short factual context only.
        - Grounded answers: Retrieve top semantic snippets from the user’s corpus (e.g., “segments”).
        - Per‑chat isolation: Every chat uses a fresh corpus for transcript + attachments.
        - Optional transparency: Show gateway trace on demand (reason → execute → tools).
        - Provider policy: OpenAI only. No local endpoints.

        Non‑Goals
        - No heavy project dashboards; keep it conversational.
        - No direct editing of source corpora from within the chat.

        3) Architecture
        - UI: SwiftUI single‑window chat pane with streaming tokens.
        - Providers: OpenAICompatibleChatProvider (requires OPENAI_API_KEY).
        - Memory augmentation:
          • Query: text search over segments in the selected memory corpus.
          • Snippets: top N small excerpts, truncated and re‑phrased if needed.
          • Operational context: compact counts (baselines, drift, reflections, patterns) + recent findings summary.
          • Prompt: base system prompts + memory snippets + operational line. Never expose rationale.
        - Persistence:
          • Memory corpus (selected): read‑only for retrieval.
          • Chat corpus (auto‑generated per session): write chat‑turns + attachments; optional patterns.
        - Transparency (opt‑in): fetch recent gateway /admin/recent and render timing + status only.

        4) Data Model (FountainStore)
        - Memory corpus (user‑selected):
          • pages, segments, entities, tables, analyses, baselines, drifts, reflections, patterns.
        - Chat corpus (per session):
          • chat‑turns: transcript with session metadata.
          • attachments: links from turn → pages/segments/patterns used.
          • patterns (optional): any rules/findings derived during the session.

        5) Prompting Model
        - Base system prompts describe assistant behavior: concise, user‑centric, cite when asked.
        - Memory snippets: top K (default 5), each ≤ 320 chars, newline‑separated.
        - Operational context: single sentence (e.g., “history: baselines=1, drifts=0, reflections=1; findings: 1 error, 2 warn”).
        - No chain‑of‑thought; redact secrets; never echo internal diagnostics.

        6) Controls & Policies
        - Discretion level (High/Visible): default High (silent); Visible shows source chips.
        - Model selection: env‑driven OPENAI_MODEL with a compact picker.
        - Safety: redact sensitive patterns before prompt injection; cap token budgets.

        7) OpenAPI Surfaces (future)
        - If a server is introduced: /memchat/session (create), /memchat/trace (recent ops), /memchat/export (bundle chat corpus).
        - Specs live under FountainSpecCuration/openapi/v1/memchat.yml; generated clients via Apple plugin.

        8) Milestones
        M1: Local MVP
          • Streaming chat with OpenAI‑compatible provider.
          • Memory retrieval from selected corpus.
          • Per‑chat corpus persistence + attachments.
        M2: Transparency & UX polish
          • On‑demand gateway trace; source chips.
          • Basic model picker; resend last prompt.
        M3: Operational hardening
          • Redaction, token budgets, error remediation.
          • Export chat corpus bundle.
        M4: Server & OpenAPI (optional)
          • Session lifecycle endpoints; CI hooks; sharing flows.

        9) Success Metrics
        - Latency: P50 < 2.0s streaming start with OpenAI.
        - Relevance: user‑rated ≥ 4/5 for groundedness.
        - Zero unexpected disclosures: no latent chain‑of‑thought leaks.

        10) Environment & Config
        - FOUNTAINSTORE_DIR: repo‑local store path.
        - OPENAI_API_KEY / OPENAI_API_URL.
        - FOUNTAIN_GATEWAY_URL (trace), AWARENESS_URL (optional counts).

        Seeded by memchat-concept-seed into corpus: \(corpusId)
        """
    }
}
