import SwiftUI

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
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var instruments: [Components.Schemas.Instrument] = []
    @Published var suggestions: [Components.Schemas.SuggestedLink] = []
    @Published var links: [Components.Schemas.Link] = []
    @Published var vendor: Components.Schemas.VendorIdentity? = nil
    @Published var snapshotSummary: String = ""
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
        for s in suggestions {
            let l = s.link
            _ = try? await c.createLink(l)
        }
        await refreshLinks()
    }

    func refreshLinks() async {
        guard let c = api as? PatchBayClient else { return }
        if let list = try? await c.listLinks() { links = list }
    }
    func deleteLink(_ id: String) async {
        guard let c = api as? PatchBayClient else { return }
        try? await c.deleteLink(id: id)
        await refreshLinks()
    }
}

struct ContentView: View {
    @StateObject var state: AppState
    @StateObject var vm = EditorVM()
    init(state: AppState = AppState()) { _state = StateObject(wrappedValue: state) }
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Instruments list (left)
            List(state.instruments, id: \.id) { i in
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
            }
            .navigationTitle("Instruments")
            .toolbar {
                ToolbarItem { Button("Auto‑noodle (CI/PE)") { Task { await state.autoNoodle() } } }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            // Canvas center with zoom container (pinch/scroll)
            ZoomContainer(zoom: $vm.zoom, translation: $vm.translation) {
                EditorCanvas()
                    .environmentObject(vm)
                    .background(Color(NSColor.textBackgroundColor))
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
                }
            }
        } detail: {
            InspectorPane()
                .environmentObject(state)
                .padding(12)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        }
        .task { await state.refresh() }
        .environmentObject(vm)
    }

    private func seedVM() -> EditorVM {
        vm.grid = 24
        vm.zoom = 1.0
        vm.nodes = [
            PBNode(id: "A", title: "A", x: 60, y: 60, w: 200, h: 120, ports: [
                .init(id: "out", side: .right, dir: .output),
                .init(id: "in", side: .left, dir: .input)
            ]),
            PBNode(id: "B", title: "B", x: 360, y: 180, w: 220, h: 140, ports: [
                .init(id: "in", side: .left, dir: .input),
                .init(id: "out", side: .right, dir: .output)
            ]),
        ]
        vm.edges = [ PBEdge(from: "A.out", to: "B.in") ]
        return vm
    }
}

struct InspectorPane: View {
    enum Tab: String, CaseIterable { case instruments = "Instruments", links = "Links", vendor = "Vendor", corpus = "Corpus" }
    @EnvironmentObject var state: AppState
    @State private var tab: Tab = .links
    @State private var selectedInstrumentIndex: Int = 0
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
            case .vendor:
                vendorView
            case .corpus:
                corpusView
            }
        }
        .task { await state.refreshLinks() }
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
                Button("Apply All") { Task { await state.applyAllSuggestions() } }
            }
            if state.suggestions.isEmpty { Text("No suggestions yet").foregroundColor(.secondary) }
            ScrollView {
                ForEach(Array(state.suggestions.enumerated()), id: \.0) { _, s in
                    Text("• \(s.reason) — conf: \(String(format: "%.2f", s.confidence ?? 0))")
                        .font(.system(.body, design: .monospaced))
                    if let l = Optional(s.link) {
                        Button("Apply") { Task {
                            if let c = state.api as? PatchBayClient { _ = try? await c.createLink(l) }
                            await state.refreshLinks()
                        } }
                    }
                }
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Applied Links").font(.headline)
                Spacer()
                Button("Refresh") { Task { await state.refreshLinks() } }
            }
            if state.links.isEmpty { Text("No applied links").foregroundColor(.secondary) }
            ScrollView {
                ForEach(state.links, id: \.id) { link in
                    HStack {
                        Text(linkSummaryNew(link)).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Delete") { Task { await state.deleteLink(link.id) } }
                    }
                }
            }
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

// MARK: - Helpers
extension ContentView {
    fileprivate func addInstrumentNode(_ inst: Components.Schemas.Instrument) {
        let id = inst.id
        // If node with same id exists, select it
        if vm.node(by: id) != nil { vm.selection = id; vm.selected = [id]; return }
        let node = PBNode(
            id: id,
            title: inst.title ?? inst.id,
            x: inst.x ?? 120,
            y: inst.y ?? 120,
            w: inst.w ?? 240,
            h: inst.h ?? 140,
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
