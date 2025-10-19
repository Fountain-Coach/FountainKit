import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct MemChatSavePlan {
    static func main() async {
        verifyLauncherSignature()
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "memchat-app"
        let store = resolveStore()
        do { try await store.createCorpus(corpusId) } catch { /* ignore if exists */ }

        let pageId = "plan:memchat-features"
        let page = Page(corpusId: corpusId, pageId: pageId, url: "store://plan/memchat/features", host: "store", title: "MemChat — Feature Plan")
        _ = try? await store.addPage(page)

        let text = featurePlan()
        let segId = "\(pageId):\(Int(Date().timeIntervalSince1970))"
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: segId, pageId: pageId, kind: "plan", text: text))
        print("Saved MemChat feature plan into corpus=\(corpusId) page=\(pageId) segment=\(segId)")
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

    static func featurePlan() -> String {
        return """
        MemChat — Chat App Feature Plan

        1) Core Chat UX
        - Multiline editor, Cmd+Return to send, Return for newline
        - Streaming output with smooth rendering and Stop
        - Retry / Regenerate / Edit & Resend
        - Markdown rendering (code blocks + copy)
        - Clear errors with inline retry

        2) Session Management
        - New Chat, rename session, quick switcher
        - Persistent history with autosave
        - Search across sessions and within a chat
        - Export/Import (JSON) and share transcript

        3) Model & Provider
        - Model picker (OpenAI/local)
        - Connection test in Settings
        - Token/latency counters and generation controls

        4) Semantic Memory & Context
        - Select memory corpus (read-only retrieval)
        - Per‑chat isolated corpus for transcript + attachments
        - Continuity digest (from continuity:*) auto-injected (hidden)
        - Optional “Show Sources” chips on answers
        - Pinned system prompts per session

        5) Transparency & Tooling (Optional)
        - Gateway/tool trace (method/path/status/latency)
        - Slash commands (/new, /rename, /sources on, /trace on)

        6) Productivity
        - Keyboard shortcuts for common actions
        - Quick copy for code and answer blocks
        - Drag-and-drop files for retrieval (local-only toggle)

        7) Multimodal (Nice-to-have)
        - Paste/drag images; TTS and push‑to‑talk
        - Screenshot-to-chat

        8) Safety & Privacy
        - No chain-of-thought; compact factual context only
        - Local-only mode; secrets in Keychain; redaction on snippets
        - Clear “Delete all data” and “Forget this chat”

        9) Reliability & Performance
        - Backoff/retry and rate-limit handling
        - Continue generation if cut; offline queue for tool calls

        10) OS Integration
        - Global hotkey; menu bar mini-chat; Services integration

        11) Extensibility
        - Plugin/tool interface (SPM + HTTP tool server)
        - Per‑project overrides (corpus, tools, policies)
        - Settings sync (optional), easy resets
        """
    }
}

