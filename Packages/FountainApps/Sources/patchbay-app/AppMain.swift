import SwiftUI
import UniformTypeIdentifiers
import FountainAIAdapters
import LLMGatewayAPI
import ApiClientsCore

@main
struct PatchBayStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup("PatchBay Studio") { ContentView() }
            .windowStyle(.titleBar)
            .windowToolbarStyle(.expanded)
            .commands {
                CommandMenu("View") {
                    Button("Fit to View") { NotificationCenter.default.post(name: .pbZoomFit, object: nil) }
                        .keyboardShortcut("0", modifiers: [.command])
                    Button("Actual Size (100%)") { NotificationCenter.default.post(name: .pbZoomActual, object: nil) }
                        .keyboardShortcut("1", modifiers: [.command])
                    Button("Zoom In") { /* handled in toolbar */ }
                        .keyboardShortcut("=", modifiers: [.command])
                    Button("Zoom Out") { /* handled in toolbar */ }
                        .keyboardShortcut("-", modifiers: [.command])
                }
                CommandMenu("Edit") {
                    Button("Delete") { NotificationCenter.default.post(name: .pbDelete, object: nil) }
                        .keyboardShortcut(.delete, modifiers: [])
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app becomes active and front-most when launched from Terminal
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        if ProcessInfo.processInfo.environment["PATCHBAY_WRITE_BASELINES"] == "1" {
            Task { @MainActor in
                await writeBaselinesAndExit()
            }
        }
    }

    @MainActor
    private func writeBaselinesAndExit() async {
        // Local mock API to keep app-rendered snapshots identical to test baselines
        struct SnapMockAPI: PatchBayAPI {
            func listInstruments() async throws -> [Components.Schemas.Instrument] {
                let schema = Components.Schemas.PropertySchema(version: 1, properties: [
                    .init(name: "zoom", _type: .float)
                ])
                let ident = Components.Schemas.InstrumentIdentity(
                    manufacturer: "Fountain", product: "Mock", displayName: "Mock#1", instanceId: "m1", muid28: 0,
                    hasUMPInput: true, hasUMPOutput: true
                )
                let a = Components.Schemas.Instrument(
                    id: "A", kind: .init(rawValue: "mvk.triangle")!, title: "A",
                    x: 0, y: 0, w: 100, h: 80, identity: ident, propertySchema: schema
                )
                let b = Components.Schemas.Instrument(
                    id: "B", kind: .init(rawValue: "mvk.quad")!, title: "B",
                    x: 0, y: 0, w: 100, h: 80, identity: ident, propertySchema: schema
                )
                return [a, b]
            }
            func suggestLinks(nodeIds: [String]) async throws -> [Components.Schemas.SuggestedLink] {
                let l = Components.Schemas.CreateLink(kind: .property, property: .init(from: "A.zoom", to: "B.zoom", direction: .a_to_b), ump: nil)
                return [.init(link: l, reason: "matched property zoom", confidence: 0.9)]
            }
            // Unused in snapshots
            func createInstrument(id: String, kind: Components.Schemas.InstrumentKind, title: String?, x: Int, y: Int, w: Int, h: Int) async throws -> Components.Schemas.Instrument? { nil }
        }
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let baseDir = cwd.appendingPathComponent(".fountain/artifacts", isDirectory: true)
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        // initial-open 1440x900 (infinite artboard)
        let vm = EditorVM()
        let state = AppState(api: SnapMockAPI())
        let content = ContentView(state: state).environmentObject(vm)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 60_000_000)
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: rep)
            let img = NSImage(size: host.bounds.size); img.addRepresentation(rep)
            let out = baseDir.appendingPathComponent("patchbay-initial-open.tiff")
            try? img.tiffRepresentation?.write(to: out)
            fputs("[snap] wrote \(out.path)\n", stderr)
        }
        // initial-open 1280x800
        let vmP = EditorVM()
        let contentP = ContentView(state: AppState(api: SnapMockAPI())).environmentObject(vmP)
        let hostP = NSHostingView(rootView: contentP)
        hostP.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        hostP.layoutSubtreeIfNeeded()
        if let repP = hostP.bitmapImageRepForCachingDisplay(in: hostP.bounds) {
            hostP.cacheDisplay(in: hostP.bounds, to: repP)
            let imgP = NSImage(size: hostP.bounds.size); imgP.addRepresentation(repP)
            let outP = baseDir.appendingPathComponent("patchbay-initial-open-1280x800-portrait.tiff")
            try? imgP.tiffRepresentation?.write(to: outP)
            fputs("[snap] wrote \(outP.path)\n", stderr)
        }
        // basic-canvas 640x480
        let vm2 = EditorVM(); vm2.grid = 24; vm2.zoom = 1.0
        vm2.nodes = [
            PBNode(id: "A", title: "A", x: 60, y: 60, w: 200, h: 120, ports: [.init(id: "out", side: .right, dir: .output)]),
            PBNode(id: "B", title: "B", x: 360, y: 180, w: 220, h: 140, ports: [.init(id: "in", side: .left, dir: .input)])
        ]
        vm2.edges = [ PBEdge(from: "A.out", to: "B.in") ]
        let cHost = NSHostingView(rootView: EditorCanvas().environmentObject(vm2))
        cHost.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        cHost.layoutSubtreeIfNeeded()
        if let rep2 = cHost.bitmapImageRepForCachingDisplay(in: cHost.bounds) { cHost.cacheDisplay(in: cHost.bounds, to: rep2)
            let img2 = NSImage(size: cHost.bounds.size); img2.addRepresentation(rep2)
            let out2 = baseDir.appendingPathComponent("patchbay-basic-canvas.tiff")
            try? img2.tiffRepresentation?.write(to: out2)
            fputs("[snap] wrote \(out2.path)\n", stderr)
        }
        exit(0)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var instruments: [Components.Schemas.Instrument] = []
    @Published var suggestions: [Components.Schemas.SuggestedLink] = []
    @Published var links: [Components.Schemas.Link] = []
    @Published var stored: [Components.Schemas.StoredGraph] = []
    @Published var vendor: Components.Schemas.VendorIdentity? = nil
    @Published var snapshotSummary: String = ""
    struct ActionLogItem: Identifiable { let id = UUID().uuidString; let time = Date(); let action: String; let detail: String; let diff: String }
    @Published var runLog: [ActionLogItem] = []
    struct ChatMessage: Identifiable { let id = UUID().uuidString; let role: String; let text: String }
    @Published var chat: [ChatMessage] = []
    @Published var allowedFunctions: [String] = []
    @Published var plannedSteps: [PlannerFunctionCall] = []
    let api: PatchBayAPI
    init(api: PatchBayAPI = PatchBayClient()) { self.api = api }
    func refresh() async {
        if let list = try? await api.listInstruments() { instruments = list }
    }
    func autoNoodle() async {
        if let s = try? await api.suggestLinks(nodeIds: instruments.map { $0.id }) { suggestions = s }
    }
    func loadVendor() async {
        if let c = api as? PatchBayClient, let v = try? await c.getVendorIdentity() { vendor = v }
    }
    func saveVendor() async {
        guard let v = vendor, let c = api as? PatchBayClient else { return }
        try? await c.putVendorIdentity(v)
        addLog(action: "put-vendor-identity", detail: "saved", diff: "")
    }
    func makeSnapshot() async {
        guard let c = api as? PatchBayClient else { return }
        if let s = try? await c.createCorpusSnapshot() {
            let ic = s.instruments?.count ?? 0
            let lc = s.links?.count ?? 0
            snapshotSummary = "instruments=\(ic), links=\(lc)"
        }
    }
    func applyAllSuggestions() async {
        guard let c = api as? PatchBayClient else { return }
        let before = links.count
        for s in suggestions {
            let l = s.link
            _ = try? await c.createLink(l)
        }
        await refreshLinks()
        let after = links.count
        addLog(action: "apply-all-suggestions", detail: "count=\(suggestions.count)", diff: "links: \(before)→\(after)")
    }

    func refreshLinks() async {
        guard let c = api as? PatchBayClient else { return }
        if let list = try? await c.listLinks() { links = list }
    }
    func deleteLink(_ id: String) async {
        guard let c = api as? PatchBayClient else { return }
        let before = links.count
        try? await c.deleteLink(id: id)
        await refreshLinks()
        let after = links.count
        addLog(action: "delete-link", detail: id, diff: "links: \(before)→\(after)")
    }

    func refreshStore() async {
        guard let c = api as? PatchBayClient else { return }
        if let list = try? await c.listStoredGraphs() { stored = list }
    }
    func addLog(action: String, detail: String, diff: String) {
        runLog.insert(.init(action: action, detail: detail, diff: diff), at: 0)
        if runLog.count > 50 { runLog.removeLast(runLog.count - 50) }
    }

    func ask(question: String, vm: EditorVM) async {
        chat.append(.init(role: "user", text: question))
        func summarize() -> String {
            let nodes = vm.nodes
            let edges = vm.edges
            let countUMP = edges.filter { $0.from.contains("ump") || $0.to.contains("ump") }.count
            let countProp = edges.count - countUMP
            var s = "Scene: \(nodes.count) nodes; \(edges.count) links (UMP=\(countUMP), property=\(countProp)).\n"
            if !nodes.isEmpty {
                s += "Nodes:\n" + nodes.map { "- \($0.id): \($0.title ?? $0.id)" }.joined(separator: "\n") + "\n"
            }
            if !edges.isEmpty {
                s += "Links:\n" + edges.map { "- \($0.from) → \($0.to)" }.joined(separator: "\n")
            }
            return s
        }
        let q = question.lowercased()
        if q.contains("apply suggestions") || q.contains("apply all") {
            await applyAllSuggestions()
            chat.append(.init(role: "assistant", text: "Applied suggestions. Links now: \(links.count)."))
            return
        }
        if q.contains("suggest") || q.contains("auto") {
            await autoNoodle()
            chat.append(.init(role: "assistant", text: "Fetched suggestions (\(suggestions.count)). Type ‘apply suggestions’ to apply all."))
            return
        }
        if q.contains("corpus") || q.contains("snapshot") {
            if let c = api as? PatchBayClient {
                if let s = try? await c.createCorpusSnapshot() {
                    let ic = s.instruments?.count ?? 0
                    let lc = s.links?.count ?? 0
                    chat.append(.init(role: "assistant", text: "Corpus snapshot: instruments=\(ic), links=\(lc).\n\n" + summarize()))
                    return
                }
            }
        }
        // Optional LLM Assistant via Gateway (feature-flagged)
        if ProcessInfo.processInfo.environment["PATCHBAY_ASSISTANT_LLM"] == "1" {
            let base = ProcessInfo.processInfo.environment["GATEWAY_URL"].flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:8080")!
            let tokenProvider: GatewayChatClient.TokenProvider = { ProcessInfo.processInfo.environment["GATEWAY_TOKEN"] }
            let client = GatewayChatClient(baseURL: base, tokenProvider: tokenProvider)
            let model = ProcessInfo.processInfo.environment["GATEWAY_MODEL"] ?? "gpt-4o-mini"
            let req = GroundedPromptBuilder.makeChatRequest(model: model, userQuestion: question, nodes: vm.nodes, edges: vm.edges)
            do {
                let resp = try await client.complete(request: req)
                // Try function_call first
                let actions = OpenAPIActionParser.parse(from: resp.functionCall)
                if !actions.isEmpty {
                    let applied = await execute(actions: actions, vm: vm)
                    chat.append(.init(role: "assistant", text: applied))
                    return
                }
                // Fallback to answer text
                let inferred = OpenAPIActionParser.parse(fromText: resp.answer)
                if !inferred.isEmpty {
                    let applied = await execute(actions: inferred, vm: vm)
                    chat.append(.init(role: "assistant", text: applied))
                } else {
                    chat.append(.init(role: "assistant", text: resp.answer))
                }
                return
            } catch {
                chat.append(.init(role: "assistant", text: "LLM error: \(error.localizedDescription)\n\n" + summarize()))
                return
            }
        }
        // Planner (control plane) — default path
        do {
            let plannerURL = URL(string: ProcessInfo.processInfo.environment["PLANNER_URL"] ?? "http://127.0.0.1:8003")!
            let planner = MinimalPlannerClient(baseURL: plannerURL)
            // Discover allowed function_ids from ToolsFactory and include as hint
            if allowedFunctions.isEmpty {
                if let tfBase = URL(string: ProcessInfo.processInfo.environment["TOOLS_FACTORY_URL"] ?? "http://127.0.0.1:8011") {
                    let tf = MinimalToolsFactoryClient(baseURL: tfBase)
                    if let resp = try? await tf.listTools(page: 1, pageSize: 200), let funcs = resp.functions {
                        let ids = funcs.filter { f in
                            (f.http_path?.lowercased().contains("/audiotalk/") ?? false) || (f.http_path?.lowercased().contains("/patchbay/") ?? false)
                        }.map { $0.function_id }
                        await MainActor.run { self.allowedFunctions = ids }
                    }
                }
            }
            let hint = allowedFunctions.isEmpty ? "" : "\nAllowed functions: " + allowedFunctions.joined(separator: ", ")
            let objective = "PatchBay Scene (deterministic)\n\n" + summarize() + "\n\nUser: " + question + "\n\nOnly use registered OpenAPI operationIds. " + hint
            let plan = try await planner.reason(objective: objective)
            if let steps = plan.steps, !steps.isEmpty {
                await MainActor.run { self.plannedSteps = steps }
                chat.append(.init(role: "assistant", text: "Plan with \(steps.count) steps ready. Use Run to apply individual steps."))
                return
            } else {
                chat.append(.init(role: "assistant", text: "No plan returned.\n\n" + summarize()))
                return
            }
        } catch {
            chat.append(.init(role: "assistant", text: "Planner error: \(error.localizedDescription)\n\n" + summarize()))
            return
        }
    }

    @MainActor
    func runPlannedStep(idx index: Int) async {
        guard index >= 0 && index < plannedSteps.count else { return }
        let plannerURL = URL(string: ProcessInfo.processInfo.environment["PLANNER_URL"] ?? "http://127.0.0.1:8003")!
        let planner = MinimalPlannerClient(baseURL: plannerURL)
        let step = plannedSteps[index]
        let req = PlannerPlanExecutionRequest(objective: "assistant-step", steps: [step])
        do {
            _ = try await planner.execute(req)
            await refreshLinks()
            addLog(action: "planner-exec-step", detail: step.name, diff: "links: \(links.count)")
        } catch {
            chat.append(.init(role: "assistant", text: "Execute error: \(error.localizedDescription)"))
        }
    }

    @MainActor
    func runAllPlannedSteps() async {
        guard !plannedSteps.isEmpty else { return }
        let plannerURL = URL(string: ProcessInfo.processInfo.environment["PLANNER_URL"] ?? "http://127.0.0.1:8003")!
        let planner = MinimalPlannerClient(baseURL: plannerURL)
        let req = PlannerPlanExecutionRequest(objective: "assistant-plan", steps: plannedSteps)
        do {
            _ = try await planner.execute(req)
            await refreshLinks()
            addLog(action: "planner-exec-all", detail: "\(plannedSteps.count) steps", diff: "links: \(links.count)")
        } catch {
            chat.append(.init(role: "assistant", text: "Execute error: \(error.localizedDescription)"))
        }
    }

    @MainActor
    func removePlannedStep(idx index: Int) {
        guard index >= 0 && index < plannedSteps.count else { return }
        plannedSteps.remove(at: index)
    }

    @MainActor
    private func execute(actions: [OpenAPIAction], vm: EditorVM) async -> String {
        guard let c = api as? PatchBayClient else { return "No API client bound." }
        var applied: [String] = []
        for a in actions {
            guard a.service == "patchbay-service" else { continue }
            switch a.operationId {
            case "createLink":
                if let body = a.body, let data = try? JSONEncoder().encode(body), let link = try? JSONDecoder().decode(Components.Schemas.CreateLink.self, from: data) {
                    _ = try? await c.createLink(link)
                    await refreshLinks()
                    if link.kind == .property, let p = link.property, let from = p.from, let to = p.to {
                        _ = vm.ensureEdge(from: (from.split(separator: ".").first.map(String.init) ?? "", from.split(separator: ".").last.map(String.init) ?? ""),
                                          to: (to.split(separator: ".").first.map(String.init) ?? "", to.split(separator: ".").last.map(String.init) ?? ""))
                        vm.transientGlowEdge(fromRef: from, toRef: to)
                    }
                    applied.append("createLink")
                }
            case "deleteLink":
                if let id = a.pathParams?["id"] { try? await c.deleteLink(id: id); await refreshLinks(); applied.append("deleteLink:\(id)") }
            default:
                continue
            }
        }
        if applied.isEmpty { return "No applicable actions found." }
        return "Applied actions: \(applied.joined(separator: ", "))."
    }
}

struct ContentView: View {
    @StateObject var state: AppState
    @StateObject var vm = EditorVM()
    init(state: AppState = AppState()) { _state = StateObject(wrappedValue: state) }
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.automatic)) {
            // Instruments list (left)
            List(selection: .constant(Optional<String>.none)) {
                ForEach(state.instruments, id: \.id) { i in
                    HStack(alignment: .center, spacing: 8) {
                        InstrumentIcon(kind: i.kind.rawValue)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.title ?? i.id).font(.body)
                            Text("Kind: \(i.kind.rawValue)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .onTapGesture(count: 2) {
                        // Double-click instrument to add a node to the canvas
                        addInstrumentNode(i)
                    }
                    .tag(i.id)
                }
            }
            .navigationTitle("Instruments")
            .toolbar { AddInstrumentToolbar(state: state, vm: vm) }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            // Canvas center with zoom container (pinch/scroll) and key input (arrow-keys nudge)
            KeyInputContainer(onKey: { event in
                let flags = event.modifierFlags
                let stepMult = flags.contains(.option) ? 5 : 1
                switch event.keyCode {
                case 123: vm.nudgeSelected(dx: -1 * stepMult, dy: 0)
                case 124: vm.nudgeSelected(dx: 1 * stepMult, dy: 0)
                case 125: vm.nudgeSelected(dx: 0, dy: 1 * stepMult)
                case 126: vm.nudgeSelected(dx: 0, dy: -1 * stepMult)
                default: break
                }
            }) {
                ZoomContainer(zoom: $vm.zoom, translation: $vm.translation) {
                    EditorCanvas()
                        .environmentObject(vm)
                        .environmentObject(state)
                        .background(Color(NSColor.textBackgroundColor))
                }
            }
            .navigationTitle("PatchBay Canvas")
            .navigationSplitViewColumnWidth(min: 600, ideal: 900, max: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Toggle(isOn: $vm.connectMode) { Label("Connect", systemImage: vm.connectMode ? "link" : "link.badge.plus") }
                    HStack(spacing: 4) {
                        Button { vm.zoom = max(0.25, vm.zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                        Button { vm.zoom = min(3.0, vm.zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                    }
                    Menu("Canvas") {
                        Button("Fit to View") { NotificationCenter.default.post(name: .pbZoomFit, object: nil) }
                        Divider()
                        Menu("Grid") {
                            Button("8 px (major ×5)") { vm.grid = 8; vm.majorEvery = 5 }
                            Button("12 px (major ×5)") { vm.grid = 12; vm.majorEvery = 5 }
                            Button("16 px (major ×5)") { vm.grid = 16; vm.majorEvery = 5 }
                            Button("24 px (major ×5)") { vm.grid = 24; vm.majorEvery = 5 }
                        }
                    }
                    Button {
                        // Add a generic node near origin, snapped to grid
                        let g = max(4, vm.grid)
                        vm.addNode(at: CGPoint(x: CGFloat(g*5), y: CGFloat(g*5)))
                        if let id = vm.selection {
                            // Ensure default ports so noodling works immediately
                            vm.addPort(to: id, side: .left, dir: .input, id: "in", type: "data")
                            vm.addPort(to: id, side: .right, dir: .output, id: "out", type: "data")
                        }
                    } label: { Label("Add Node", systemImage: "plus.square.on.square") }
                    Button {
                        // Open instrument preview (e.g., chat window) via registry
                        if let sel = vm.selection, let inst = state.instruments.first(where: { $0.id == sel }), let module = AppInstrumentRegistry.module(for: inst.kind.rawValue) {
                            module.openPreviewIfAvailable(id: sel, state: state, vm: vm)
                        }
                    } label: { Label("Open", systemImage: "rectangle.badge.plus") }
                    .help("Open instrument UI/preview when available")
                    .disabled({ () -> Bool in
                        guard let sel = vm.selection, let inst = state.instruments.first(where: { $0.id == sel }) else { return true }
                        return AppInstrumentRegistry.module(for: inst.kind.rawValue) == nil
                    }())
                }
            }
        }
        .task {
            await state.refresh()
            await state.refreshStore()
            // Seed a small welcome scene on first open when canvas is empty.
            if vm.nodes.isEmpty { seedWelcomeScene() }
        }
        .environmentObject(vm)
    }

    private func seedWelcomeScene() {
        vm.grid = 16
        vm.zoom = 1.0
        // Nodes
        let midiIn = PBNode(
            id: "midiIn",
            title: "MIDI In",
            x: 80, y: 80, w: 200, h: 120,
            ports: [
                .init(id: "umpOut", side: .right, dir: .output, type: "ump"),
                .init(id: "out", side: .right, dir: .output, type: "data")
            ]
        )
        let mapper = PBNode(
            id: "Mapper_1",
            title: "Mapper",
            x: 280, y: 120, w: 220, h: 120,
            ports: [
                .init(id: "in", side: .left, dir: .input, type: "data"),
                .init(id: "out", side: .right, dir: .output, type: "data")
            ]
        )
        let instrument = PBNode(
            id: "Instrument_1",
            title: "Instrument",
            x: 540, y: 140, w: 240, h: 140,
            ports: [
                .init(id: "umpIn", side: .left, dir: .input, type: "ump"),
                .init(id: "in", side: .left, dir: .input, type: "data"),
                .init(id: "out", side: .right, dir: .output, type: "data")
            ]
        )
        vm.nodes = [midiIn, mapper, instrument]
        // Edges (UMP and property)
        vm.edges = [
            PBEdge(from: "midiIn.umpOut", to: "Instrument_1.umpIn"),
            PBEdge(from: "Mapper_1.out", to: "Instrument_1.in")
        ]
        vm.selected = []
        vm.selection = nil
        state.addLog(action: "welcome-scene", detail: "seeded", diff: "nodes: 0→\(vm.nodes.count)")
    }
}

// MARK: - Add Instrument UI

struct AddInstrumentToolbar: View {
    @ObservedObject var state: AppState
    @ObservedObject var vm: EditorVM
    @State private var showSheet: Bool = false
    var body: some View {
        Button { NSApp.activate(ignoringOtherApps: true); if let w = NSApp.keyWindow ?? NSApp.windows.first { w.makeKeyAndOrderFront(nil) }; showSheet = true } label: { Label("Add Instrument", systemImage: "plus") }
            .sheet(isPresented: $showSheet) { AddInstrumentSheet(state: state, vm: vm, dismiss: { showSheet = false }) }
            .help("Create an instrument on the PatchBay service and place it on the canvas")
    }
}

struct AddInstrumentSheet: View {
    @ObservedObject var state: AppState
    @ObservedObject var vm: EditorVM
    var dismiss: () -> Void
    @State private var kind: String = "mvk.triangle"
    @State private var title: String = ""
    @State private var working: Bool = false
    @State private var errorText: String = ""
    @FocusState private var titleFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Add Instrument").font(.title3).bold(); Spacer(); Button("Close") { dismiss() } }
            Picker("Kind", selection: $kind) {
                Text("Triangle (mvk.triangle)").tag("mvk.triangle")
                Text("Textured Quad (mvk.quad)").tag("mvk.quad")
                Text("AudioTalk Chat (audiotalk.chat)").tag("audiotalk.chat")
                Text("External CoreMIDI (external.coremidi)").tag("external.coremidi")
            }
            FocusTextField(text: $title, placeholder: "Title (optional)", initialFocus: true)
                .frame(height: 22)
            if !errorText.isEmpty { Text(errorText).foregroundColor(.red).font(.caption) }
            HStack { Spacer(); Button(working ? "Creating…" : "Create") { Task { await create() } }.disabled(working) }
        }
        .padding(14)
        .frame(minWidth: 420)
        .onAppear {
            // Ensure app is active and the sheet captures typing
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { titleFocused = true }
        }
    }
    @MainActor
    private func create() async {
        guard let c = state.api as? PatchBayClient else { return }
        working = true; defer { working = false }
        let id = "inst_\(Int(Date().timeIntervalSince1970))"
        let g = max(4, vm.grid)
        let (x,y,w,h): (Int,Int,Int,Int)
        switch kind {
        case "mvk.quad": (x,y,w,h) = (g*20, g*14, 260, 180)
        case "audiotalk.chat": (x,y,w,h) = (g*32, g*9, 280, 180)
        case "external.coremidi": (x,y,w,h) = (g*12, g*8, 220, 140)
        default: (x,y,w,h) = (g*10, g*10, 220, 160)
        }
        let k = Components.Schemas.InstrumentKind(rawValue: kind) ?? .init(rawValue: "mvk.triangle")!
        do {
            if let inst = try await c.createInstrument(id: id, kind: k, title: title.isEmpty ? nil : title, x: x, y: y, w: w, h: h) {
                await state.refresh()
                var ports: [PBPort] = []
                ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
                ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
                if inst.identity.hasUMPInput == true { ports.append(.init(id: "umpIn", side: .left, dir: .input, type: "ump")) }
                if inst.identity.hasUMPOutput == true { ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump")) }
                let node = PBNode(id: inst.id, title: inst.title, x: inst.x, y: inst.y, w: inst.w, h: inst.h, ports: ports)
                vm.nodes.append(node)
                vm.selection = inst.id
                dismiss()
            } else {
                errorText = "Service did not return instrument"
            }
        } catch { errorText = error.localizedDescription }
    }
}
struct InspectorPane: View {
    enum Tab: String, CaseIterable { case instruments = "Instruments", links = "Links", rules = "Rules", vendor = "Vendor", corpus = "Corpus" }
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    @State private var tab: Tab = .links
    @State private var selectedInstrumentIndex: Int = 0
    @State private var storeId: String = "scene-1"
    @State private var previewLink: Components.Schemas.CreateLink? = nil
    @State private var showPreview: Bool = false
    @State private var showApplyAllConfirm: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)
            switch tab {
            case .instruments:
                instrumentsView
            case .links:
                linksView
            case .rules:
                rulesView
            case .vendor:
                vendorView
            case .corpus:
                corpusView
            }
        }
        .task { await state.refreshLinks() }
    }
    @ViewBuilder var rulesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Canvas Rules").font(.headline)
            let checks = computeRules()
            ForEach(checks, id: \.title) { c in
                HStack {
                    Image(systemName: c.ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundColor(c.ok ? .green : .red)
                    Text(c.title).font(.system(.body, design: .monospaced))
                    Spacer()
                    if !c.detail.isEmpty { Text(c.detail).foregroundColor(.secondary).font(.caption) }
                }
            }
            Text("These local checks will be backed by RulesKit service calls.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
    @ViewBuilder var instrumentsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instruments (\(state.instruments.count))").font(.headline)
            Picker("Instrument", selection: $selectedInstrumentIndex) {
                ForEach(Array(state.instruments.enumerated()), id: \.0) { idx, i in Text(i.title ?? i.id).tag(idx) }
            }
            .onAppear { if selectedInstrumentIndex >= state.instruments.count { selectedInstrumentIndex = 0 } }
            if state.instruments.indices.contains(selectedInstrumentIndex) {
                let inst = state.instruments[selectedInstrumentIndex]
                Text("Kind: \(inst.kind.rawValue)").font(.subheadline)
                Text("Properties:").font(.subheadline)
                ScrollView { VStack(alignment: .leading, spacing: 4) {
                    ForEach(inst.propertySchema.properties, id: \.name) { p in
                        Text("• \(p.name) [\(p._type.rawValue)]")
                            .font(.system(.body, design: .monospaced))
                    }
                } }
            } else {
                Text("No instrument selected").foregroundColor(.secondary)
            }
        }
    }
    @ViewBuilder var linksView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Suggestions").font(.headline)
                Spacer()
                Button("Refresh") { Task { await state.autoNoodle() } }
                Button("Apply All") { showApplyAllConfirm = true }
            }
            if state.suggestions.isEmpty { Text("No suggestions yet").foregroundColor(.secondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("suggestions-top")
                    ForEach(Array(state.suggestions.enumerated()), id: \.0) { _, s in
                        Text("• \(s.reason) — conf: \(String(format: "%.2f", s.confidence ?? 0))")
                            .font(.system(.body, design: .monospaced))
                        if let l = Optional(s.link) { Button("Apply") { previewLink = l; showPreview = true } }
                    }
                }
                .onChange(of: state.suggestions.count) { _, _ in withAnimation { proxy.scrollTo("suggestions-top", anchor: .top) } }
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Applied Links").font(.headline)
                Spacer()
                Button("Refresh") { Task { await state.refreshLinks() } }
            }
            if state.links.isEmpty { Text("No applied links").foregroundColor(.secondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("links-top")
                    ForEach(state.links, id: \.id) { link in
                        HStack {
                            Text(linkSummaryNew(link)).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Delete") { Task { await state.deleteLink(link.id) } }
                        }
                    }
                }
                .onChange(of: state.links.count) { _, _ in withAnimation { proxy.scrollTo("links-top", anchor: .top) } }
            }
            Divider().padding(.vertical, 4)
            Text("Run Log").font(.headline)
            if state.runLog.isEmpty { Text("No actions yet").foregroundColor(.secondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("log-top")
                    ForEach(state.runLog) { item in
                        HStack(alignment: .top) {
                            Text(item.action).font(.system(.body, design: .monospaced))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.detail).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                                if !item.diff.isEmpty { Text(item.diff).font(.system(.caption, design: .monospaced)) }
                            }
                        }
                    }
                }
                .onChange(of: state.runLog.count) { _, _ in withAnimation { proxy.scrollTo("log-top", anchor: .top) } }
            }
        }
        .alert("Apply all suggestions?", isPresented: $showApplyAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Apply All") {
                Task {
                    // Apply in service and visualize on canvas
                    if let c = state.api as? PatchBayClient {
                        let before = state.links.count
                        for s in state.suggestions {
                            let l = s.link
                            _ = try? await c.createLink(l)
                            if l.kind == .property, let p = l.property, let a = p.from, let b = p.to {
                                // Ensure a canvas edge exists and glow it
                                let fa = a.split(separator: ".", maxSplits: 1).map(String.init)
                                let fb = b.split(separator: ".", maxSplits: 1).map(String.init)
                                if fa.count == 2 && fb.count == 2 {
                                    _ = vm.ensureEdge(from: (fa[0], fa[1]), to: (fb[0], fb[1]))
                                    vm.transientGlowEdge(fromRef: a, toRef: b, duration: 1.6)
                                }
                            }
                        }
                        await state.refreshLinks()
                        let after = state.links.count
                        state.addLog(action: "apply-all-suggestions", detail: "count=\(state.suggestions.count)", diff: "links: \(before)→\(after)")
                    }
                }
            }
        } message: {
            Text("Count: \(state.suggestions.count)")
        }
        .sheet(isPresented: $showPreview) {
            let link = previewLink
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview Link (JSON)").font(.headline)
                ScrollView {
                    Text(link.map(jsonString(of:)) ?? "{}").font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { previewLink = nil; showPreview = false }
                    Button("Apply") {
                        Task {
                            if let c = state.api as? PatchBayClient, let link = previewLink {
                                let before = state.links.count
                                _ = try? await c.createLink(link)
                                await state.refreshLinks()
                                let after = state.links.count
                                state.addLog(action: "create-link", detail: linkSummaryCreate(link), diff: "links: \(before)→\(after)")
                                // Mirror the new link on the canvas and glow
                                if link.kind == .property, let p = link.property, let a = p.from, let b = p.to {
                                    let fa = a.split(separator: ".", maxSplits: 1).map(String.init)
                                    let fb = b.split(separator: ".", maxSplits: 1).map(String.init)
                                    if fa.count == 2 && fb.count == 2 {
                                        _ = vm.ensureEdge(from: (fa[0], fa[1]), to: (fb[0], fb[1]))
                                        vm.transientGlowEdge(fromRef: a, toRef: b, duration: 1.6)
                                    }
                                }
                            }
                            previewLink = nil; showPreview = false
                        }
                    }
                }
            }
            .padding(12)
        }
    }
    @ViewBuilder var vendorView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Vendor Identity").font(.headline); Spacer(); Button("Load") { Task { await state.loadVendor() } } }
            let v = Binding(get: { state.vendor ?? .init() }, set: { state.vendor = $0 })
            TextField("Manufacturer ID", text: Binding(get: { v.wrappedValue.manufacturerId ?? "" }, set: { var t = v.wrappedValue; t.manufacturerId = $0; state.vendor = t }))
            HStack {
                StepperWithField(title: "Family", value: Binding(get: { v.wrappedValue.familyCode ?? 0 }, set: { var t = v.wrappedValue; t.familyCode = $0; state.vendor = t }))
                StepperWithField(title: "Model", value: Binding(get: { v.wrappedValue.modelCode ?? 0 }, set: { var t = v.wrappedValue; t.modelCode = $0; state.vendor = t }))
                StepperWithField(title: "Revision", value: Binding(get: { v.wrappedValue.revision ?? 0 }, set: { var t = v.wrappedValue; t.revision = $0; state.vendor = t }))
            }
            Picker("Subtree", selection: Binding(get: { v.wrappedValue.subtreeStrategy ?? .sequential }, set: { var t = v.wrappedValue; t.subtreeStrategy = $0; state.vendor = t })) {
                Text("sequential").tag(Components.Schemas.VendorIdentity.subtreeStrategyPayload.sequential)
                Text("hash-instanceId").tag(Components.Schemas.VendorIdentity.subtreeStrategyPayload.hash_hyphen_instanceId)
            }
            HStack { Spacer(); Button("Save") { Task { await state.saveVendor() } } }
        }
    }
    @ViewBuilder var corpusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Corpus Snapshot").font(.headline); Spacer(); Button("Create Snapshot") { Task { await state.makeSnapshot() } } }
            if !state.snapshotSummary.isEmpty { Text(state.snapshotSummary).font(.system(.body, design: .monospaced)) }
            Divider().padding(.vertical, 4)
            Text("Store (Save/Load)").font(.headline)
            HStack {
                TextField("Graph ID", text: $storeId).frame(width: 160)
                Button("Save Current") {
                    Task {
                        if let c = state.api as? PatchBayClient {
                            let doc = vm.toGraphDoc(with: state.instruments)
                            try? await c.putStoredGraph(id: storeId, doc: doc)
                            await state.refreshStore()
                        }
                    }
                }
                Spacer()
                Button("Refresh List") { Task { await state.refreshStore() } }
            }
            if state.stored.isEmpty { Text("No stored graphs").foregroundColor(.secondary) }
            ScrollView {
                ForEach(state.stored, id: \.id) { item in
                    HStack {
                        Text(item.id).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Load") {
                            Task {
                                if let c = state.api as? PatchBayClient, let sg = try? await c.getStoredGraph(id: item.id) {
                                    vm.applyGraphDoc(sg.doc)
                                }
                            }
                        }
                    }
                }
            }
            Divider().padding(.vertical, 4)
            Text("Agent Preset").font(.headline)
            HStack(spacing: 8) {
                Button("Export Agent Preset…") {
                    // Build agent preset from current GraphDoc and save via NSSavePanel
                    let doc = vm.toGraphDoc(with: state.instruments)
                    let base = (state.api as? PatchBayClient)?.baseURL ?? URL(string: "http://127.0.0.1:7090")!
                    let preset = AgentPreset.build(name: "PatchBay Scene (\(storeId))", baseURL: base, graph: doc, notes: "Generated by PatchBay Studio")
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    guard let data = try? enc.encode(preset) else { return }
                    let panel = NSSavePanel(); if #available(macOS 12.0, *) { panel.allowedContentTypes = [UTType.json] } ; panel.nameFieldStringValue = "agent-preset.json"
                    panel.begin { resp in
                        if resp == .OK, let url = panel.url {
                            do { try data.write(to: url); state.addLog(action: "export-agent-preset", detail: url.lastPathComponent, diff: "") } catch { }
                        }
                    }
                }
                Text("Exports a lightweight agent config for PatchBay actions.")
                    .foregroundColor(.secondary)
            }
            // Export of a fixed A4 page removed in infinite artboard mode.
        }
    }
}


struct StepperWithField: View {
    var title: String
    @Binding var value: Int
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Stepper("", value: $value, in: 0...65535)
            TextField("\(title)", value: $value, formatter: NumberFormatter())
                .frame(width: 60)
        }
    }
}

struct InstrumentIcon: View {
    var kind: String
    var body: some View {
        switch kind {
        case "mvk.triangle": Image(systemName: "triangle.fill")
        case "mvk.quad": Image(systemName: "square.inset.filled")
        default: Image(systemName: "circle.grid.3x3")
        }
    }
}

// MARK: - Assistant (AudioTalk-style Q&A)
struct AssistantPane: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    @State private var chatInput: String = "What instruments and links are present?"
    @FocusState private var chatFocused: Bool
    @State private var expanded: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assistant").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(state.chat) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.role.uppercased()).font(.caption).foregroundColor(.secondary)
                            Text(m.text).font(.system(.body, design: .monospaced))
                        }
                        .padding(8)
                        .background(m.role == "user" ? Color(NSColor.windowBackgroundColor) : Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }.frame(minHeight: 220)
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    // Multiline, expandable input
                    TextEditor(text: $chatInput)
                        .font(.body)
                        .frame(minHeight: expanded ? 140 : 44, maxHeight: expanded ? 220 : 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                        .animation(.easeInOut(duration: 0.2), value: expanded)
                        .focused($chatFocused)
                    if chatInput.isEmpty {
                        Text("Ask about this scene…")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }
                }
                HStack(spacing: 8) {
                    Button("Send") { Task { await state.ask(question: chatInput, vm: vm) } }
                        .keyboardShortcut(.return, modifiers: [.command])
                    Button(expanded ? "Collapse" : "Expand") { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
                        .help("Toggle input height (Cmd+Return to send)")
                }
            }
            .onAppear {
                // Autofocus chat when the app first launches; user can click elsewhere to move focus
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { chatFocused = true }
            }
            Divider().padding(.vertical, 6)
            // Keep quick actions visible
            HStack(spacing: 8) {
                Button("Suggestions") { Task { await state.autoNoodle(); state.chat.append(.init(role: "assistant", text: "Fetched suggestions (\(state.suggestions.count)).")) } }
                Button("Apply All") { Task { await state.applyAllSuggestions() } }
                Button("Corpus Snapshot") { Task { await state.makeSnapshot(); state.chat.append(.init(role: "assistant", text: state.snapshotSummary)) } }
            }
            if !state.plannedSteps.isEmpty {
                Divider().padding(.vertical, 6)
                Text("Planned Steps").font(.headline)
                HStack(spacing: 8) {
                    Button("Run All") { Task { await state.runAllPlannedSteps() } }
                    Button("Clear Plan") { withAnimation { state.plannedSteps.removeAll() } }
                }
                ForEach(Array(state.plannedSteps.enumerated()), id: \.offset) { pair in
                    let idx = pair.offset
                    let step = pair.element
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text(step.name).font(.system(.body, design: .monospaced))
                            if let data = try? JSONEncoder().encode(step.arguments.mapValues { $0 }), let json = String(data: data, encoding: .utf8) {
                                Text(json).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Run") { Task { await state.runPlannedStep(idx: idx) } }
                            Button("Remove") { withAnimation { state.removePlannedStep(idx: idx) } }
                        }
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
    }
}

// MARK: - Helpers
extension ContentView {
    fileprivate func addInstrumentNode(_ inst: Components.Schemas.Instrument) {
        let id = inst.id
        // If node with same id exists, select it
        if vm.node(by: id) != nil { vm.selection = id; vm.selected = [id]; return }
        let node = PBNode(
            id: id,
            title: inst.title ?? inst.id,
            x: inst.x,
            y: inst.y,
            w: inst.w,
            h: inst.h,
            ports: []
        )
        vm.nodes.append(node)
        // Ports: UMP based on identity + generic data pair
        if inst.identity.hasUMPInput == true { vm.addPort(to: id, side: .left, dir: .input, id: "umpIn", type: "ump") }
        if inst.identity.hasUMPOutput == true { vm.addPort(to: id, side: .right, dir: .output, id: "umpOut", type: "ump") }
        vm.addPort(to: id, side: .left, dir: .input, id: "in", type: "data")
        vm.addPort(to: id, side: .right, dir: .output, id: "out", type: "data")
        vm.selection = id
        vm.selected = [id]
    }
}

// MARK: - Local Rules (to be migrated to RulesKit)
extension InspectorPane {
    struct RuleCheck { let title: String; let ok: Bool; let detail: String }
    func computeRules() -> [RuleCheck] {
        var out: [RuleCheck] = []
        // Infinite artboard: page fit/margins are not applicable
        out.append(.init(title: "PageFit", ok: true, detail: "infinite-artboard"))
        // Pane width policy placeholder
        let pw = RulesKitFacade.checkPaneWidthPolicy()
        out.append(.init(title: "PaneWidthRange(left 200–320, right 260–460)", ok: pw.ok, detail: pw.detail))
        return out
    }
}

private func linkSummaryNew(_ l: Components.Schemas.Link) -> String {
    switch l.kind {
    case .property:
        let a = l.property?.from ?? "?"
        let b = l.property?.to ?? "?"
        return "prop: \(a) → \(b)"
    case .ump:
        if let m = l.ump {
            let s = m.source
            let to = m.to
            let msg = s.message.rawValue
            return "ump: ep=\(s.endpointId) g=\(s.group) ch=\(s.channel) \(msg) → \(to)"
        }
        return "ump: (incomplete)"
    default:
        return l.id
    }
}

private func linkSummaryCreate(_ l: Components.Schemas.CreateLink) -> String {
    switch l.kind {
    case .property:
        let a = l.property?.from ?? "?"
        let b = l.property?.to ?? "?"
        return "prop: \(a) → \(b)"
    case .ump:
        if let m = l.ump {
            let s = m.source
            let msg = s.message.rawValue
            return "ump: ep=\(s.endpointId) g=\(s.group) ch=\(s.channel) \(msg) → \(m.to)"
        }
        return "ump: (incomplete)"
    default:
        return "create-link"
    }
}

private func jsonString<T: Encodable>(of value: T) -> String {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) { return s }
    return "{ }"
}
private func linkSummary(_ l: Components.Schemas.Link) -> String {
    switch l.kind {
    case .property:
        let a = l.property?.from ?? "?"
        let b = l.property?.to ?? "?"
        return "prop: \(a) → \(b)"
    case .ump:
        if let s = l.ump?.source, let to = l.ump?.to {
            let msg = s.message.rawValue
            return "ump: ep=\(s.endpointId) g=\(s.group) ch=\(s.channel) \(msg) → \(to)"
        }
        return "ump: (incomplete)"
    default:
        return l.id
    }
}
