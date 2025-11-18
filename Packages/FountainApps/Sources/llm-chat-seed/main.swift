import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct LLMChatSeed {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

        let corpusId = env["CORPUS_ID"] ?? "llm-chat"
        let store = resolveStore()
        do {
            _ = try await store.createCorpus(corpusId, metadata: ["app": "llm-chat", "kind": "teatro+instrument"])
        } catch {
            // corpus may already exist; ignore
        }

        let pageId = "prompt:llm-chat"
        let page = Page(
            corpusId: corpusId,
            pageId: pageId,
            url: "store://prompt/llm-chat",
            host: "store",
            title: "LLM Chat Instrument — Teatro Prompt"
        )
        _ = try? await store.addPage(page)

        let creation = creationPrompt()
        _ = try? await store.addSegment(.init(
            corpusId: corpusId,
            segmentId: "\(pageId):teatro",
            pageId: pageId,
            kind: "teatro.prompt",
            text: creation
        ))

        // Facts segment: instrument identity, PE surface, and invariants.
        let facts: [String: Any] = [
            "instruments": [[
                "id": "llm-chat",
                "manufacturer": "Fountain",
                "product": "LLMChat",
                "instanceId": "llm-chat-1",
                "displayName": "LLM Chat (Ollama)",
                "pe": [
                    "prompt.text",
                    "prompt.cursorOffset",
                    "prompt.mode",
                    "prompt.canSend",
                    "thread.scrollOffset",
                    "thread.selectedMessageId",
                    "thread.filter.role",
                    "llm.modelId",
                    "llm.temperature",
                    "llm.maxTokens",
                    "llm.systemPrompt.enabled",
                    "run.current.status",
                    "run.current.tokensPrompt",
                    "run.current.tokensCompletion",
                    "run.current.latencyMs"
                ]
            ]],
            "properties": [
                "prompt.text": [
                    "type": "string"
                ],
                "prompt.cursorOffset": [
                    "type": "int",
                    "min": 0
                ],
                "prompt.mode": [
                    "type": "enum",
                    "values": ["chat", "command", "edit"],
                    "default": "chat"
                ],
                "prompt.canSend": [
                    "type": "bool"
                ],
                "thread.scrollOffset": [
                    "type": "float",
                    "min": 0.0,
                    "max": 1.0,
                    "default": 0.0
                ],
                "thread.selectedMessageId": [
                    "type": "string",
                    "nullable": true
                ],
                "thread.filter.role": [
                    "type": "enum",
                    "values": ["all", "user", "assistant", "tool"],
                    "default": "all"
                ],
                "llm.modelId": [
                    "type": "string",
                    "default": "llama3.1:8b"
                ],
                "llm.temperature": [
                    "type": "float",
                    "min": 0.0,
                    "max": 2.0,
                    "default": 0.7
                ],
                "llm.maxTokens": [
                    "type": "int",
                    "min": 16,
                    "max": 32768,
                    "default": 1024
                ],
                "llm.systemPrompt.enabled": [
                    "type": "bool",
                    "default": true
                ],
                "run.current.status": [
                    "type": "enum",
                    "values": ["idle", "streaming", "failed"],
                    "default": "idle"
                ],
                "run.current.tokensPrompt": [
                    "type": "int",
                    "min": 0
                ],
                "run.current.tokensCompletion": [
                    "type": "int",
                    "min": 0
                ],
                "run.current.latencyMs": [
                    "type": "float",
                    "min": 0.0
                ]
            ],
            "invariants": [
                "Pressing SEND when prompt.canSend = true appends a user message and starts a new run.",
                "While run.current.status = streaming, prompt.canSend = false and a visual streaming indicator is visible.",
                "thread.scrollOffset = 0 shows the most recent messages; 1.0 snaps to the earliest messages.",
                "Adjusting thread.filter.role filters the visible messages but does not delete history.",
                "llm.modelId, llm.temperature, and llm.maxTokens are read at the start of a run and remain stable for that run."
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addSegment(.init(
                corpusId: corpusId,
                segmentId: "\(pageId):facts",
                pageId: pageId,
                kind: "facts",
                text: json
            ))
        }

        print("Seeded LLM Chat instrument prompt → corpus=\(corpusId) page=\(pageId)")
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(
                    fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path
                        + String(dir.dropFirst()),
                    isDirectory: true
                )
            } else {
                url = URL(fileURLWithPath: dir, isDirectory: true)
            }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                return FountainStoreClient(client: disk)
            }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let disk = try? DiskFountainStoreClient(
            rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)
        ) {
            return FountainStoreClient(client: disk)
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

    static func creationPrompt() -> String {
        """
        Scene: LLM Chat — Local Instrument (Ollama‑Backed)

        Text:
        - Window: macOS titlebar, 960×720 pt. Content is split vertically:
          • Upper region (thread): scrollable chat transcript with bubble styling.
          • Lower region (prompt): single‑line or multi‑line text field plus a small row of controls.
        - Provider: by default, the app talks directly to a local Ollama instance via its OpenAI‑compatible endpoint
          (http://127.0.0.1:11434/v1/chat/completions). No secrets live in env; this is a local‑only instrument.

        Prompt editor instrument:
        - Properties:
          • prompt.text — full text in the input field (UTF‑8).
          • prompt.cursorOffset — zero‑based cursor offset in UTF‑16 code units.
          • prompt.mode — \"chat\" (default), optional \"command\" or \"edit\" for tooling experiments.
          • prompt.canSend — true when the field is non‑empty and no run is actively streaming.
        - Behaviour:
          • Pressing Return (or clicking SEND) when prompt.canSend = true emits a chat request and clears prompt.text.
          • While a run is streaming, prompt.canSend = false and the SEND control visually reflects that.
          • Escape clears the input and returns prompt.mode = \"chat\".

        Chat thread instrument:
        - Properties:
          • thread.scrollOffset — logical scroll position in [0,1]; 0 shows the bottom (most recent messages), 1 the very top.
          • thread.selectedMessageId — optional message id to highlight or show in a details pane.
          • thread.filter.role — filter over roles: \"all\" | \"user\" | \"assistant\" | \"tool\".
        - Behaviour:
          • New messages append at the bottom; when thread.scrollOffset is near 0, the view autoscrolls.
          • When the user scrolls up, autoscroll is disabled until they scroll back near the bottom.
          • Selecting a message toggles its highlight and may pin it in a small inspector.

        LLM controls + run inspector:
        - Properties:
          • llm.modelId — model name understood by Ollama (e.g., \"llama3.1:8b\").
          • llm.temperature — 0.0–2.0; 0.7 by default.
          • llm.maxTokens — maximum completion tokens for a single run.
          • llm.systemPrompt.enabled — when false, user prompts go through without any extra instructions.
          • run.current.status — \"idle\" | \"streaming\" | \"failed\".
          • run.current.tokensPrompt / run.current.tokensCompletion — token counts for the most recent run.
          • run.current.latencyMs — wall‑clock latency of the most recent completed run, in milliseconds.
        - Behaviour:
          • The next chat run snapshots llm.* properties at the moment SEND is pressed and uses them for the whole run.
          • While streaming, run.current.status = \"streaming\" and a small indicator is visible near the thread.
          • On completion, run.current.status = \"idle\" and metrics update; on error, status = \"failed\" with an error banner.

        Property Exchange surface:
        - Exposed properties for agents and robots:
          • prompt.text
          • prompt.cursorOffset
          • prompt.mode
          • prompt.canSend
          • thread.scrollOffset
          • thread.selectedMessageId
          • thread.filter.role
          • llm.modelId
          • llm.temperature
          • llm.maxTokens
          • llm.systemPrompt.enabled
          • run.current.status
          • run.current.tokensPrompt
          • run.current.tokensCompletion
          • run.current.latencyMs
        - These properties map onto the instrument spec llm-chat.yml and facts in the agents corpus so that MIDI 2.0 PE
          can drive prompt updates, scroll navigation, and run controls without having to know about Ollama directly.

        Testing notes:
        - Unit‑level tests drive the instrument via its OpenAPI surface and assert:
          • prompt.canSend toggling rules,
          • scrollOffset clamping and autoscroll behaviour,
          • run status transitions (idle → streaming → idle/failed).
        - PB‑VRT snapshots cover at least:
          • empty thread,
          • simple conversation (two turns),
          • failure banner.
        """
    }
}

