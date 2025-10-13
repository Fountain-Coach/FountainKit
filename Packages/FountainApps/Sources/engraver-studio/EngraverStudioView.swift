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
    @FocusState private var promptFocused: Bool

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

                HStack(spacing: 12) {
                    Picker("Model", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    TextEditor(text: $draftPrompt)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 120)
                        .focused($promptFocused)
                        .foregroundColor(Color.primary)
                        .background(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .onAppear {
                            DispatchQueue.main.async {
                                promptFocused = true
                            }
                        }

                    VStack(spacing: 8) {
                        Button {
                            sendPrompt()
                        } label: {
                            Label("Engrave", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.state == .streaming)

                        Button("Cancel") {
                            viewModel.cancelStreaming()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.state != .streaming)
                    }
                    .frame(maxWidth: 140)
                }
                .padding()

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
            NSApp.activate(ignoringOtherApps: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
