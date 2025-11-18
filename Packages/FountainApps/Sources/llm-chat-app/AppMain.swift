import AppKit
import Foundation
import FountainGUIKit
import FountainAICore
import ProviderLocalLLM
import LauncherSignature

private struct LLMChatMessage {
    enum Role {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

private struct LLMChatState {
    var messages: [LLMChatMessage] = []
    var streamingText: String = ""
    var inputText: String = ""
    var runStatus: RunStatus = .idle

    enum RunStatus {
        case idle
        case streaming
        case failed
    }
}

@MainActor
final class LLMChatView: FGKRootView {
    var state = LLMChatState()

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(bounds)

        let margin: CGFloat = 12
        let lineSpacing: CGFloat = 6
        let maxWidth = bounds.width - margin * 2

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let roleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        var y = bounds.height - margin

        func drawLine(_ text: String, attrs: [NSAttributedString.Key: Any]) {
            let attr = NSAttributedString(string: text, attributes: attrs)
            var rect = attr.boundingRect(with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
            rect.origin.x = margin
            rect.origin.y = y - rect.height
            attr.draw(in: rect)
            y = rect.minY - lineSpacing
        }

        for message in state.messages {
            let role = (message.role == .user) ? "User" : "Assistant"
            drawLine(role, attrs: roleAttrs)
            drawLine(message.text, attrs: baseAttrs)
        }

        if !state.streamingText.isEmpty {
            drawLine("Assistant (streaming)", attrs: roleAttrs)
            drawLine(state.streamingText, attrs: baseAttrs)
        }

        // Prompt area at the bottom
        let promptLabel = "Prompt:"
        let promptAttr = NSAttributedString(string: promptLabel, attributes: roleAttrs)
        let promptRect = NSRect(x: margin,
                                y: margin + 4,
                                width: maxWidth,
                                height: 16)
        promptAttr.draw(in: promptRect)

        let inputAttr = NSAttributedString(string: state.inputText, attributes: baseAttrs)
        let inputRect = NSRect(x: margin,
                               y: promptRect.maxY + 2,
                               width: maxWidth,
                               height: 20)
        inputAttr.draw(in: inputRect)
    }
}

@MainActor
final class LLMChatInstrumentTarget: FGKEventTarget {
    private unowned let view: LLMChatView
    private var provider: any CoreChatStreaming

    init(view: LLMChatView) {
        self.view = view
        let endpoint = LLMChatInstrumentTarget.ollamaEndpoint()
        self.provider = LocalLLMProvider.make(endpoint: endpoint)
    }

    func handle(event: FGKEvent) -> Bool {
        switch event {
        case .keyDown(let key):
            handleKeyDown(key)
            return true
        case .scroll:
            // No-op for now; could be wired to logical thread.scrollOffset later.
            return true
        default:
            return false
        }
    }

    private func handleKeyDown(_ key: FGKKeyEvent) {
        guard view.state.runStatus != .streaming else { return }

        // Return / Enter sends the current prompt.
        if key.keyCode == 36 { // kVK_Return
            sendCurrentPrompt()
            return
        }

        // Delete / backspace
        if key.keyCode == 51 {
            if !view.state.inputText.isEmpty {
                view.state.inputText.removeLast()
                view.needsDisplay = true
            }
            return
        }

        // Append visible characters
        if !key.characters.isEmpty {
            let scalars = key.characters.unicodeScalars
            // Filter out control characters (arrows, function keys, etc.)
            if scalars.allSatisfy({ !$0.properties.isControl }) {
                view.state.inputText.append(contentsOf: key.characters)
                view.needsDisplay = true
            }
        }
    }

    private func sendCurrentPrompt() {
        let text = view.state.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        view.state.inputText = ""
        view.state.streamingText = ""
        view.state.runStatus = .streaming
        view.state.messages.append(.init(role: .user, text: text))
        view.needsDisplay = true

        let request = makeCoreRequest(model: LLMChatInstrumentTarget.defaultModel(), userText: text)
        let start = Date()

        Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in self.provider.stream(request: request, preferStreaming: true) {
                    await MainActor.run {
                        if chunk.isFinal {
                            let answer = chunk.response?.answer ?? chunk.text
                            self.view.state.streamingText = ""
                            self.view.state.runStatus = .idle
                            self.view.state.messages.append(.init(role: .assistant, text: answer))
                            self.view.needsDisplay = true
                            let _ = Date().timeIntervalSince(start) * 1000.0
                        } else {
                            self.view.state.streamingText += chunk.text
                            self.view.needsDisplay = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.view.state.streamingText = "Error: \(error.localizedDescription)"
                    self.view.state.runStatus = .failed
                    self.view.needsDisplay = true
                }
            }
        }
    }

    private static func ollamaEndpoint() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let s = env["OLLAMA_OPENAI_ENDPOINT"], let u = URL(string: s) {
            return u
        }
        if let base = env["OLLAMA_URL"], !base.isEmpty,
           let u = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/chat/completions") {
            return u
        }
        return URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
    }

    private static func defaultModel() -> String {
        ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "codellama"
    }

    private func makeCoreRequest(model: String, userText: String) -> CoreChatRequest {
        CoreChatRequest(model: model, messages: [
            .init(role: .user, content: userText)
        ])
    }
}

@MainActor
private final class LLMChatAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentSize = NSSize(width: 720, height: 520)
        let frame = NSRect(origin: .zero, size: contentSize)

        let rootNode = FGKNode(
            instrumentId: "fountain.coach/agent/llm-chat/service",
            frame: frame,
            properties: [],
            target: nil
        )

        let rootView = LLMChatView(frame: frame, rootNode: rootNode)
        rootView.wantsLayer = true

        let target = LLMChatInstrumentTarget(view: rootView)
        rootNode.target = target

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Chat (Ollama)"
        window.contentView = rootView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(rootView)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

@main
enum LLMChatAppMain {
    static func main() {
        verifyLauncherSignature()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = LLMChatAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

