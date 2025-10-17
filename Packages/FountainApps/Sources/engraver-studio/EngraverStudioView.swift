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

    @Environment(\.openURL) private var openURL
    @State private var draftPrompt: String = ""
    @State private var selectedTurnID: UUID?
    @State private var showErrorAlert: Bool = false
    @State private var showDiagnostics: Bool = false
    @State private var promptEditorIsFocused: Bool = false
    @State private var showSemanticBrowser: Bool = false
    @AppStorage("EngraverStudio.ShowLeftPane") private var showLeftPane: Bool = true
    @AppStorage("EngraverStudio.ShowRightPane") private var showRightPane: Bool = true
    @State private var toast: String? = nil


    var body: some View {
        HStack(spacing: 0) {
            if showLeftPane {
                BootSidePane(viewModel: viewModel)
                    .frame(width: 340)
                Divider()
            }

            VStack(spacing: 0) {
                TopBar(viewModel: viewModel,
                       showLeft: $showLeftPane,
                       showRight: $showRightPane)
                Divider()
                mainPane
            }

            if showRightPane {
                Divider()
                RightPane(viewModel: viewModel)
                    .frame(width: 380)
            }
        }
        .onChange(of: viewModel.lastError) { _, newValue in
            showErrorAlert = newValue != nil
            if let msg = newValue { withAnimation { toast = msg } ; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { if toast == msg { toast = nil } } } }
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
        .sheet(isPresented: $showSemanticBrowser) {
            SemanticBrowserSheet(viewModel: viewModel, openURL: { url in openURL(url) })
                .frame(minWidth: 520, minHeight: 360)
        }
        .overlay(alignment: .top) {
            if let toast {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(toast).font(.caption)
                    Button { withAnimation { self.toast = nil } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 12)
            }
        }
    }

    // no-op placeholder retained for future logic

    private var mainPane: some View {
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

            mainTranscriptGroup

            Divider()

            composerPane

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
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { showSemanticBrowser = true }
                } label: {
                    Label("Semantic Browser", systemImage: "globe")
                }
            }
        }
    }

    @ViewBuilder
    private var mainTranscriptGroup: some View {
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
    }

    private var composerPane: some View {
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
    @State private var copied = false

    var body: some View {
        GroupBox(label: HStack {
            Text("Diagnostics")
            Spacer()
            Button {
                copyAll(); flashCopied()
            } label: {
                if copied {
                    Label("Copied", systemImage: "checkmark")
                } else {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.borderless)
            .help("Copy all diagnostics to clipboard")
        }) {
            if messages.isEmpty {
                Text("Enable ENGRAVER_DEBUG=1 to capture verbose logs.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
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
                .textSelection(.enabled)
                .frame(minHeight: 140, maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button("Copy All") { copyAll() }
        }
    }

    private func copyAll() {
        let text = messages.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func flashCopied() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

@available(macOS 13.0, *)
private struct BootTrailPane: View {
    @ObservedObject var viewModel: EngraverChatViewModel
    @Environment(\.openURL) private var openURL
    var onProceed: () -> Void
    @State private var webPreviewItem: IdentifiableURL? = nil

    private var stateText: String {
        switch viewModel.environmentState {
        case .unavailable(let reason): return "Unavailable — \(reason)"
        case .idle: return "Idle"
        case .checking: return "Checking…"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .running: return "Running"
        case .failed(let reason): return "Failed — \(reason)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Engraver Studio — Boot Sequence")
                    .font(.title2.weight(.semibold))
                Spacer()
                statusBadge
                Button {
                    onProceed()
                } label: {
                    Label("Proceed to Studio", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
            }

            Text("Starting local services for the FULL RANGE experience. This may take a moment on first launch.")
                .font(.callout)
                .foregroundStyle(.secondary)

            controlRow

            Divider()

            HStack(alignment: .top, spacing: 16) {
                servicesPanel
                logsPanel
            }

            if viewModel.environmentIsRunning {
                Text("All core services are up. You can start engraving.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 600, alignment: .topLeading)
        .task {
            // Ensure we probe status when entering the boot pane
            viewModel.refreshEnvironmentStatus()
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.environmentState)
        .sheet(item: $webPreviewItem) { item in
            VStack(spacing: 0) {
                HStack {
                    Text(item.url.absoluteString).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button { openURL(item.url) } label: { Label("Open in Browser", systemImage: "safari") }
                        .buttonStyle(.borderless)
                }
                .padding(8)
                Divider()
                EmbeddedWebView(url: item.url)
                    .frame(minWidth: 720, minHeight: 480)
            }
            .frame(minWidth: 720, minHeight: 520)
        }
    }

    private var statusBadge: some View {
        Group {
            switch viewModel.environmentState {
            case .running:
                Label("\(stateText)", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            case .starting, .checking:
                HStack(spacing: 8) { ProgressView(); Text(stateText).font(.caption) }
            case .failed:
                Label("\(stateText)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .stopping:
                HStack(spacing: 8) { ProgressView(); Text(stateText).font(.caption) }
            case .idle:
                Label("Idle", systemImage: "pause.circle").foregroundStyle(.secondary)
            case .unavailable:
                Label("Unavailable", systemImage: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.startEnvironment(includeExtras: true)
            } label: {
                Label("Start FULL RANGE", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.environmentIsBusy || viewModel.environmentIsRunning)

            Button {
                viewModel.stopEnvironment(includeExtras: true, force: false)
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.environmentIsBusy || !viewModel.environmentIsRunning)

            Button(role: .destructive) {
                viewModel.stopEnvironment(includeExtras: true, force: true)
            } label: {
                Label("Force Clean", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .help("Kill stray processes and release ports")

            Button {
                viewModel.fixAllServices()
            } label: {
                Label("Fix All", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.bordered)
            .help("Kill non-up PIDs and restart missing services")

            Button {
                viewModel.refreshEnvironmentStatus()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Spacer()
        }
    }

    private var servicesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Services")
                .font(.headline)
            if viewModel.environmentServices.isEmpty {
                Text("Probing…").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.environmentServices) { svc in
                    HStack(spacing: 8) {
                        stateDot(svc.state)
                        Text(svc.name).font(.callout)
                        Spacer()
                        Text(":\(svc.port)").font(.caption).foregroundStyle(.secondary)
                        if let pid = svc.pid { Text("PID \(pid)").font(.caption).foregroundStyle(.secondary) }
                        controlButtons(for: svc)
                    }
                }
            }
        }
        .frame(width: 320, alignment: .topLeading)
    }

    private func stateDot(_ s: EnvironmentServiceState) -> some View {
        let color: Color = (s == .up) ? .green : (s == .down ? .red : .gray)
        return Circle().fill(color).frame(width: 9, height: 9)
    }

    @ViewBuilder
    private func controlButtons(for svc: EnvironmentServiceStatus) -> some View {
        HStack(spacing: 6) {
            Button {
                if let url = URL(string: "http://127.0.0.1:\(svc.port)/metrics") { webPreviewItem = IdentifiableURL(url: url) }
            } label: { Image(systemName: "globe") }
            .buttonStyle(.borderless)
            .help("Open metrics (embedded)")

            if let pid = svc.pid {
                Button(role: .destructive) {
                    viewModel.forceKill(pid: pid)
                } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
                .help("Kill PID \(pid)")
            }

            Button {
                viewModel.restart(service: svc)
            } label: { Image(systemName: "arrow.triangle.2.circlepath") }
            .buttonStyle(.borderless)
            .help("Restart service")
        }
    }

    private var logsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Boot Trail")
                    .font(.headline)
                Spacer()
                CopyButton(textProvider: { viewModel.environmentLogs.map(\.line).joined(separator: "\n") })
                .buttonStyle(.borderless)
                .help("Copy all boot logs")
            }
            if viewModel.environmentLogs.isEmpty {
                Text("Waiting for logs…").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.environmentLogs) { entry in
                            Text("[\(entry.timestamp.ISO8601Format())] \(entry.line)")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(minHeight: 240)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

@available(macOS 13.0, *)
private struct BootSidePane: View {
    @ObservedObject var viewModel: EngraverChatViewModel
    @State private var webPreviewItem: IdentifiableURL? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statusDot(viewModel.environmentState)
                Text(headerText)
                    .font(.headline)
                Spacer()
                if viewModel.environmentIsRunning {
                    Label("ALL GREEN", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                }
            }
            controlRow
            Divider()
            servicesPanel
        }
        .padding(12)
        .sheet(item: $webPreviewItem) { item in
            VStack(spacing: 0) {
                HStack { Text(item.url.absoluteString).font(.caption).textSelection(.enabled); Spacer(); Button { openURL(item.url) } label: { Label("Open in Browser", systemImage: "safari") } .buttonStyle(.borderless) }
                    .padding(8)
                Divider()
                EmbeddedWebView(url: item.url).frame(minWidth: 720, minHeight: 480)
            }
            .frame(minWidth: 720, minHeight: 520)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Button { viewModel.startEnvironment(includeExtras: true) } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.environmentIsBusy || viewModel.environmentIsRunning)
            Button { viewModel.stopEnvironment(includeExtras: true, force: false) } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.bordered)
                .disabled(viewModel.environmentIsBusy || !viewModel.environmentIsRunning)
            Button(role: .destructive) { viewModel.stopEnvironment(includeExtras: true, force: true) } label: { Label("Force", systemImage: "trash") }
                .buttonStyle(.bordered)
            Button { viewModel.fixAllServices() } label: { Label("Fix All", systemImage: "wrench.and.screwdriver") }
                .buttonStyle(.bordered)
            Button { viewModel.refreshEnvironmentStatus() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(.borderless)
        }
    }

    private var servicesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Services").font(.subheadline)
            if viewModel.environmentServices.isEmpty {
                Text("Probing…").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.environmentServices) { svc in
                    HStack(spacing: 8) {
                        stateDot(svc.state)
                        Text(svc.name).font(.callout)
                        Spacer()
                        Text(":\(svc.port)").font(.caption).foregroundStyle(.secondary)
                        if let pid = svc.pid { Text("PID \(pid)").font(.caption).foregroundStyle(.secondary) }
                        Button { if let url = URL(string: "http://127.0.0.1:\(svc.port)/metrics") { webPreviewItem = IdentifiableURL(url: url) } } label: { Image(systemName: "globe") }.buttonStyle(.borderless).help("Metrics")
                        if let pid = svc.pid { Button(role: .destructive) { viewModel.forceKill(pid: pid) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Kill") }
                        Button { viewModel.restart(service: svc) } label: { Image(systemName: "arrow.triangle.2.circlepath") }.buttonStyle(.borderless).help("Restart")
                    }
                }
            }
        }
    }

    private func stateDot(_ s: EnvironmentServiceState) -> some View {
        let color: Color = (s == .up) ? .green : (s == .down ? .red : .gray)
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func statusDot(_ s: EnvironmentOverallState) -> some View {
        let color: Color
        switch s {
        case .running: color = .green
        case .starting, .checking: color = .yellow
        case .failed: color = .orange
        case .stopping: color = .gray
        case .idle: color = .gray
        case .unavailable: color = .red
        }
        return Circle().fill(color).frame(width: 10, height: 10)
    }

    private var headerText: String {
        switch viewModel.environmentState {
        case .running: return "Environment — Running"
        case .starting: return "Environment — Starting…"
        case .checking: return "Environment — Checking…"
        case .stopping: return "Environment — Stopping…"
        case .idle: return "Environment — Idle"
        case .failed(_): return "Environment — Failed"
        case .unavailable: return "Environment — Unavailable"
        }
    }
}

@available(macOS 13.0, *)
private struct RightPane: View {
    @ObservedObject var viewModel: EngraverChatViewModel
    @AppStorage("EngraverStudio.RightPaneTab") private var rightTabRaw: String = "logs"
    private enum Tab: String { case logs, diagnostics }
    private var tab: Tab { get { Tab(rawValue: rightTabRaw) ?? .logs } nonmutating set { rightTabRaw = newValue.rawValue } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(get: { tab }, set: { tab = $0 })) {
                Text("Boot Trail").tag(Tab.logs)
                Text("Diagnostics").tag(Tab.diagnostics)
                }
            .pickerStyle(.segmented)

            if tab == .logs {
                GroupBox(label: Text("Boot Trail")) {
                    if viewModel.environmentLogs.isEmpty {
                        Text("Waiting for logs…").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView { LazyVStack(alignment: .leading, spacing: 6) { ForEach(viewModel.environmentLogs) { entry in Text("[\(entry.timestamp.ISO8601Format())] \(entry.line)").font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) } } }
                            .textSelection(.enabled)
                            .frame(minHeight: 260)
                    }
                }
            } else if tab == .diagnostics {
                DiagnosticsPanel(messages: viewModel.diagnostics)
            }
            GroupBox(label: HStack { Text("Gateway Traffic"); Spacer(); Button { Task { await viewModel.refreshGatewayTraffic() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.borderless) }) {
                if viewModel.trafficEvents.isEmpty {
                    Text("No recent traffic. Press Refresh.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView { LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.trafficEvents) { ev in
                            HStack(spacing: 8) {
                                statusDot(ev.status)
                                Text("\(ev.method)").font(.caption.weight(.semibold))
                                Text(ev.path).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(ev.status)").font(.caption2)
                                Text("\(ev.durationMs)ms").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    } }
                    .textSelection(.enabled)
                    .frame(minHeight: 160)
                }
            }
            Spacer()
        }
        .padding(12)
    }

    private func statusDot(_ status: Int) -> some View {
        let color: Color = (200...299).contains(status) ? .green : (status == 429 ? .orange : .red)
        return Circle().fill(color).frame(width: 6, height: 6)
    }
}

    private struct IdentifiableURL: Identifiable { let url: URL; var id: String { url.absoluteString } }

@available(macOS 13.0, *)
private struct CopyButton: View {
    let textProvider: () -> String
    @State private var copied = false
    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(textProvider(), forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            if copied { Label("Copied", systemImage: "checkmark") }
            else { Label("Copy", systemImage: "doc.on.doc") }
        }
    }
}

@available(macOS 13.0, *)
private struct TopBar: View {
    @ObservedObject var viewModel: EngraverChatViewModel
    @Binding var showLeft: Bool
    @Binding var showRight: Bool
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(viewModel.environmentIsRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.environmentIsRunning ? "ALL GREEN" : "Starting…")
                    .font(.caption.weight(.semibold))
            }
            Spacer()
            Toggle(isOn: $showLeft) { Image(systemName: "sidebar.left") }
                .toggleStyle(.button)
                .help(showLeft ? "Hide environment" : "Show environment")
            Toggle(isOn: $showRight) { Image(systemName: "sidebar.right") }
                .toggleStyle(.button)
                .help(showRight ? "Hide diagnostics" : "Show diagnostics")
        }
        .padding(8)
    }
}

@available(macOS 13.0, *)
private struct SemanticBrowserSheet: View {
    @ObservedObject var viewModel: EngraverChatViewModel
    let openURL: (URL) -> Void

    private var runs: [SemanticSeedRun] { viewModel.seedRuns }
    private var state: SeedOperationState { viewModel.seedingState }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The Semantic Browser indexes configured sources (remote URLs or local files) and persists the parsed segments into FountainStore.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let endpoint = viewModel.seedingBrowserEndpoint {
                    Label("Endpoint: \(endpoint.absoluteString)", systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                statusRow(title: "Pipeline", state: state)

                HStack(spacing: 12) {
                    Button {
                        viewModel.generateSeedManifests()
                    } label: {
                        Label(state.isRunning ? "Running…" : "Re-index Sources", systemImage: state.isRunning ? "hourglass" : "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isRunning)

                    if let endpoint = viewModel.seedingBrowserEndpoint {
                        Button {
                            openURL(endpoint)
                        } label: {
                            Label("Open Semantic Browser", systemImage: "safari")
                        }
                        .buttonStyle(.borderless)
                    }

                    Spacer()
                }

                Divider()

                if runs.isEmpty {
                    ContentUnavailableView(
                        "No Runs Yet",
                        systemImage: "tray",
                        description: Text("Trigger a run to seed the configured sources.")
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(runs) { run in
                            SemanticRunRow(run: run)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func statusRow(title: String, state: SeedOperationState) -> some View {
        switch state {
        case .idle:
            Label("\(title): Idle", systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 8) {
                ProgressView()
                Text("\(title) in progress…")
                    .font(.caption)
            }
        case .succeeded(let timestamp, let count):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title): Completed (\(count))")
                    Text(timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .font(.caption)
        case .failed(let message, let timestamp):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title) failed")
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
            .font(.caption)
        }
    }

    private struct SemanticRunRow: View {
        let run: SemanticSeedRun

        private var labels: String { run.labels.joined(separator: ", ") }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(run.sourceName)
                        .font(.headline)
                    Spacer()
                    statusBadge
                }
                Text(run.sourceURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !labels.isEmpty {
                    Text("Labels: \(labels)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let metrics = run.metrics {
                    HStack(spacing: 12) {
                        metricTag("Pages", metrics.pagesUpserted)
                        metricTag("Segments", metrics.segmentsUpserted)
                        metricTag("Entities", metrics.entitiesUpserted)
                        metricTag("Tables", metrics.tablesUpserted)
                    }
                }

                if let message = run.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let finished = run.finishedAt {
                    Text(finished, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }

        @ViewBuilder
        private var statusBadge: some View {
            switch run.state {
            case .idle:
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .succeeded:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }

        private func metricTag(_ label: String, _ value: Int) -> some View {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                Text("\(value)")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(NSColor.textBackgroundColor))
            )
        }
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
