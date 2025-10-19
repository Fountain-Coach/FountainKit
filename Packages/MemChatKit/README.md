# MemChatKit

A discreet, context‑aware chat library for Swift projects, built on FountainAI.

- Semantic memory from a selected corpus (e.g., `segments` collection) via FountainStore (disk by default)
- Per-chat isolated persistence (each session writes to a new chat corpus)
- Discreet prompting: compact, factual context (no chain-of-thought)
- OpenAI provider only (no local endpoints)
- Optional gateway/awareness endpoints for observability
- Drop-in SwiftUI view (`MemChatView`), Teatro surface (`MemChatTeatroView`), or controller API (`MemChatController`)

## Usage

```
.package(path: "../MemChatKit")
```

```swift
import MemChatKit

struct ContentView: View {
    var body: some View {
        MemChatView(configuration: .init(memoryCorpusId: "memchat-app"))
    }
}

struct TeatroChatView: View {
    var body: some View {
        MemChatTeatroView(configuration: .init(memoryCorpusId: "memchat-app"))
    }
}
```

Or use the controller directly:

```swift
let controller = MemChatController(config: .init(memoryCorpusId: "memchat-app"))
controller.newChat()
controller.send("Hello")
```

## Configuration
- `memoryCorpusId`: Read‑only corpus used for retrieval
- `chatCollection`: Target collection name for chat turns (`chat-turns`)
- Provider: `model`, `OPENAI_API_KEY`, optional `OPENAI_API_URL` (OpenAI-only)
- Observability: `FOUNTAIN_GATEWAY_URL`, `AWARENESS_URL`
- Persistence: uses on-disk FountainStore by default. Override path with `ENGRAVER_STORE_PATH`.

## Continuity
MemChatKit automatically loads the latest `continuity:*` page from the memory corpus,
trims it, and injects it as a `ContinuityDigest` line in the system prompts.

All chat turns, system prompts (including the per‑turn “Context used” summary), and optional
analysis artifacts (baselines, drift, patterns, reflections) are persisted in FountainStore.
If the Awareness service is not configured, MemChatKit persists these artifacts directly.

## Export/Import
Use `MemChatExporter` to export a chat corpus (turns/attachments/patterns) to JSON
and import it elsewhere.

```swift
let exporter = MemChatExporter(store: store)
let data = try await exporter.export(corpusId: "chat-...")
try await exporter.import(into: "chat-restored", data: data)
```

## License
Internal FountainKit module.
