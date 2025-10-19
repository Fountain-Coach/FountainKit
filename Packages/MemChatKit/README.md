# MemChatKit

A discreet, context‑aware chat library for Swift projects, built on FountainAI.

- Semantic memory from a selected corpus (e.g., `segments` collection)
- Per‑chat isolated persistence (each session writes to a new chat corpus)
- Discreet prompting: compact, factual context (no chain‑of‑thought)
- OpenAI‑compatible provider (hosted OpenAI or local compatible endpoints)
- Optional gateway/awareness endpoints for observability
- Drop‑in SwiftUI view (`MemChatView`) or controller API (`MemChatController`)

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
- Provider: `model`, `OPENAI_API_KEY`, `OPENAI_API_URL`, `ENGRAVER_LOCAL_LLM_URL`
- Observability: `FOUNTAIN_GATEWAY_URL`, `AWARENESS_URL`

## Continuity
MemChatKit automatically loads the latest `continuity:*` page from the memory corpus,
trims it, and injects it as a `ContinuityDigest` line in the system prompts.

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
