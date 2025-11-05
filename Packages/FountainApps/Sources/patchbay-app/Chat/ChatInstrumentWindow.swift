import AppKit
import SwiftUI
import LLMGatewayAPI
import FountainAIAdapters
import FountainAICore
import ProviderLocalLLM

@MainActor
final class ChatInstrumentManager: ObservableObject {
    static let shared = ChatInstrumentManager()
    private var windows: [String: NSWindow] = [:]

    func open(for instrumentId: String, preferredProvider: String? = nil, model: String? = nil) {
        if let win = windows[instrumentId] {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = ChatSessionController()
        let view = ChatInstrumentView(controller: controller, title: "AudioTalk Chat — \(instrumentId)")
        let host = NSHostingView(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "AudioTalk Chat — \(instrumentId)"
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[instrumentId] = win
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.windows.removeValue(forKey: instrumentId) }
        }
    }
}

struct ChatInstrumentView: View {
    @ObservedObject var controller: ChatSessionController
    var title: String
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(.headline)
                Spacer()
                Text(controller.providerLabel).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(controller.messages.indices, id: \.self) { idx in
                            let m = controller.messages[idx]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.role.capitalized).font(.caption).foregroundStyle(.secondary)
                                Text(m.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(m.role == "user" ? Color(NSColor.windowBackgroundColor) : Color(NSColor.textBackgroundColor))
                            )
                        }
                        if !controller.streamingText.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Assistant").font(.caption).foregroundStyle(.secondary)
                                Text(controller.streamingText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.4))
                            )
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
            }
            Divider()
            composer
                .padding(12)
        }
        .onAppear { inputFocused = true }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message").font(.caption).foregroundStyle(.secondary)
            FocusTextView(text: $input, initialFocus: true, minHeight: 120)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25))
                )
            HStack {
                Spacer()
                Button(controller.state == .streaming ? "Streaming" : "Send") {
                    send()
                }
                .disabled(controller.state == .streaming)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { inputFocused = true; return }
        Task { await controller.send(trimmed) }
        input = ""
        inputFocused = true
    }
}

@MainActor
final class ChatSessionController: ObservableObject {
    struct Message { let role: String; let text: String }
    @Published var messages: [Message] = []
    @Published var streamingText: String = ""
    @Published var state: State = .idle
    enum State { case idle, streaming, failed }
    var providerLabel: String { useOllama() ? "Ollama" : "Gateway" }

    func send(_ text: String) async {
        messages.append(.init(role: "user", text: text))
        state = .streaming
        defer { if state == .streaming { state = .idle } }
        if useOllama() {
            await sendViaOllama(text)
        } else {
            await sendViaGateway(text)
        }
    }

    // MARK: - Providers
    private func useOllama() -> Bool {
        if ProcessInfo.processInfo.environment["PATCHBAY_USE_OLLAMA"] == "1" { return true }
        if ProcessInfo.processInfo.environment["OLLAMA_URL"] != nil { return true }
        if ProcessInfo.processInfo.environment["OLLAMA_OPENAI_ENDPOINT"] != nil { return true }
        return false
    }

    private func ollamaOpenAIEndpoint() -> URL {
        if let s = ProcessInfo.processInfo.environment["OLLAMA_OPENAI_ENDPOINT"], let u = URL(string: s) {
            return u
        }
        if let base = ProcessInfo.processInfo.environment["OLLAMA_URL"], !base.isEmpty {
            // Derive OpenAI-compat endpoint when given base like http://127.0.0.1:11434
            if let u = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/chat/completions") {
                return u
            }
        }
        return URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
    }

    private func ollamaModel() -> String {
        ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "codellama"
    }

    private func toCoreRequest(model: String, userText: String) -> CoreChatRequest {
        CoreChatRequest(model: model, messages: [
            .init(role: .user, content: userText)
        ])
    }

    private func pulse(_ deltaText: String) {
        // Emit a lightweight canvas activity so noodles can animate if desired
        NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: [
            "type": "llm.pulse",
            "chars": deltaText.count
        ])
    }

    private func sendViaOllama(_ text: String) async {
        let endpoint = ollamaOpenAIEndpoint()
        let model = ollamaModel()
        let provider = LocalLLMProvider.make(endpoint: endpoint)
        let req = toCoreRequest(model: model, userText: text)
        streamingText = ""
        do {
            for try await chunk in provider.stream(request: req, preferStreaming: true) {
                if chunk.isFinal {
                    messages.append(.init(role: "assistant", text: chunk.response?.answer ?? chunk.text))
                    streamingText = ""
                    state = .idle
                } else {
                    streamingText += chunk.text
                    pulse(chunk.text)
                }
            }
        } catch {
            streamingText = "Error: \(error.localizedDescription)"
            state = .failed
        }
    }

    private func sendViaGateway(_ text: String) async {
        let base = ProcessInfo.processInfo.environment["GATEWAY_URL"].flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:8010")!
        let tokenProvider: GatewayChatClient.TokenProvider = { ProcessInfo.processInfo.environment["GATEWAY_TOKEN"] }
        let client = GatewayChatClient(baseURL: base, tokenProvider: tokenProvider)
        let model = ProcessInfo.processInfo.environment["GATEWAY_MODEL"] ?? "gpt-4o-mini"
        let req = GroundedPromptBuilder.makeChatRequest(model: model, userQuestion: text, nodes: [], edges: [])
        do {
            let resp = try await client.complete(request: req)
            let answer = resp.answer
            messages.append(.init(role: "assistant", text: answer))
            streamingText = ""
            state = .idle
        } catch {
            streamingText = "Error: \(error.localizedDescription)"
            state = .failed
        }
    }
}
