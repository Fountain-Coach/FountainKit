import Foundation
#if canImport(SwiftUI)
import SwiftUI
import AppKit
import TeatroGUI
import EngraverChatCore

@available(macOS 13.0, *)
struct EngraverStudioView: View {
    @ObservedObject var viewModel: EngraverChatViewModel
    let systemPrompts: [String]

    @State private var draftPrompt: String = ""
    @State private var selectedTurnID: UUID?
    @State private var showErrorAlert: Bool = false
    @State private var showDiagnostics: Bool = false
    @State private var promptEditorIsFocused: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 12) {
                StreamStatusView(
                    connected: viewModel.state == .streaming,
                    acks: viewModel.turns.count,
                    nacks: viewModel.lastError == nil ? 0 : 1,
                    rtt: 0,
                    window: 0,
                    loss: 0
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if viewModel.state == .streaming {
                        TokenStreamView(tokens: viewModel.activeTokens, showBeatGrid: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                            .animation(.default, value: viewModel.activeTokens.count)
                    } else if let selectedTurn = selectedTurn {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Model: \(selectedTurn.model ?? viewModel.selectedModel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(selectedTurn.answer)
                                    .font(.body)
                                    .monospaced()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                        }
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    } else {
                        ContentUnavailableView(
                            "No Messages Yet",
                            systemImage: "ellipsis.bubble",
                            description: Text("Compose a prompt below to begin a new chat turn.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Model")
                            .font(.callout.weight(.semibold))
                            .accessibilityHidden(true)
                        Picker("", selection: $viewModel.selectedModel) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .leading)
                        .accessibilityLabel("Model")

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                sendPrompt()
                            } label: {
                                Label("Engrave", systemImage: "paperplane.fill")
                                    .frame(minWidth: 100)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.state == .streaming)

                            Button("Cancel") {
                                viewModel.cancelStreaming()
                                promptEditorIsFocused = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.state != .streaming)
                        }
                    }

                    PromptTextEditor(
                        text: $draftPrompt,
                        isFirstResponder: $promptEditorIsFocused,
                        isEditable: viewModel.state != .streaming,
                        onSubmit: {
                            sendPrompt()
                        }
                    )
                    .frame(minHeight: 110, maxHeight: 180)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if draftPrompt.isEmpty {
                            Text("Compose your prompt…")
                                .font(.callout)
                                .foregroundColor(Color.secondary.opacity(0.6))
                                .padding(.all, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .onAppear {
                        promptEditorIsFocused = true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showDiagnostics {
                    DiagnosticsPanel(messages: viewModel.diagnostics)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        selectedTurnID = nil
                    } label: {
                        Label("Clear Selection", systemImage: "line.3.horizontal.decrease")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation { showDiagnostics.toggle() }
                    } label: {
                        Label("Diagnostics", systemImage: showDiagnostics ? "eye.slash" : "eye")
                    }
                    .help("Toggle verbose diagnostics (requires ENGRAVER_DEBUG=1).")
                    .disabled(viewModel.diagnostics.isEmpty)
                }
            }
        }
        .onChange(of: viewModel.lastError) { _, newValue in
            showErrorAlert = newValue != nil
        }
        .onChange(of: viewModel.state) { _, newState in
            if newState != .streaming {
                promptEditorIsFocused = true
            }
        }
        .alert(
            "Gateway Error",
            isPresented: $showErrorAlert,
            actions: {
                Button("Dismiss", role: .cancel) { showErrorAlert = false }
            },
            message: {
                Text(viewModel.lastError ?? "Unknown error")
            }
        )
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowActivationView())
    }

    private var sidebar: some View {
        List(selection: $selectedTurnID) {
            ForEach(viewModel.turns) { turn in
                Button {
                    selectedTurnID = turn.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(turn.prompt)
                            .font(.headline)
                            .lineLimit(2)
                        Text(turn.answer)
                            .font(.caption)
                            .lineLimit(2)
                        Text(turn.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
        .listStyle(.sidebar)
    }

    private var selectedTurn: EngraverChatTurn? {
        if let selectedTurnID {
            return viewModel.turns.first(where: { $0.id == selectedTurnID })
        }
        return viewModel.turns.last
    }

    private func sendPrompt() {
        let content = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        viewModel.send(
            prompt: content,
            systemPrompts: viewModel.makeSystemPrompts(base: systemPrompts)
        )
        draftPrompt = ""
        promptEditorIsFocused = true
    }
}

@available(macOS 13.0, *)
private struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var isEditable: Bool
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        if let textView = scrollView.documentView as? NSTextView {
            configure(textView, coordinator: context.coordinator)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = (nsView.documentView as? NSTextView) else {
            return
        }
        if context.coordinator.textView !== textView {
            configure(textView, coordinator: context.coordinator)
        }

        if textView.string != text {
            textView.string = text
        }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        textView.textColor = isEditable ? NSColor.labelColor : NSColor.secondaryLabelColor

        if isFirstResponder {
            focus(textView, attempt: 0)
        } else if !isEditable {
            resign(textView, attempt: 0)
        }
    }

    private func configure(_ textView: NSTextView, coordinator: Coordinator) {
        coordinator.textView = textView
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        textView.usesFindPanel = true
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = coordinator
    }

    private func focus(_ textView: NSTextView, attempt: Int) {
        guard attempt < 10 else { return }
        DispatchQueue.main.async {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            if let window = textView.window {
                if !window.isKeyWindow {
                    window.makeKeyAndOrderFront(nil)
                }
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.focus(textView, attempt: attempt + 1)
                }
            }
        }
    }

    private func resign(_ textView: NSTextView, attempt: Int) {
        guard attempt < 10 else { return }
        DispatchQueue.main.async {
            if let window = textView.window {
                if window.firstResponder === textView {
                    window.makeFirstResponder(nil)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.resign(textView, attempt: attempt + 1)
                }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextEditor
        weak var textView: NSTextView?

        init(parent: PromptTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, textView.string != parent.text else { return }
            parent.text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            if parent.isFirstResponder == false {
                parent.isFirstResponder = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFirstResponder {
                parent.isFirstResponder = false
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               let event = NSApp.currentEvent,
               event.modifierFlags.contains(.command) {
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}

@available(macOS 13.0, *)
private struct DiagnosticsPanel: View {
    let messages: [String]

    var body: some View {
        GroupBox(label: Text("Diagnostics")) {
            if messages.isEmpty {
                Text("Enable ENGRAVER_DEBUG=1 to capture verbose logs.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

@available(macOS 13.0, *)
private struct WindowActivationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.makeKeyAndOrderFront(nil)
            }
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
