import SwiftUI
import UniformTypeIdentifiers
import FountainAIAdapters
import LLMGatewayAPI
import ApiClientsCore
import TutorDashboard
import AppKit

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
                // Canvas menu contains zoom items above; no overlay toggle (removed)
                // Edit menu: deletion disabled (dustbin-only)
                CommandMenu("Debug") {
                    Button("Dump Focus State") {
                        FocusManager.dumpFocus(label: "dump")
                    }
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app becomes a regular, foreground app even when launched via `swift run` from Terminal.
        NSApp.setActivationPolicy(.regular)
        func attemptActivate(_ remaining: Int) {
            guard remaining >= 0 else { return }
            // Try both activation paths (Apple deprecates the flag on macOS 14, but plain activate still works)
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [])
            if let win = NSApp.keyWindow ?? NSApp.windows.first {
                win.makeKeyAndOrderFront(nil)
            }
            if NSApp.isActive, NSApp.keyWindow != nil { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { attemptActivate(remaining - 1) }
        }
        attemptActivate(12) // ~1s
        if ProcessInfo.processInfo.environment["PATCHBAY_WRITE_BASELINES"] == "1" {
            Task { @MainActor in
                await writeBaselinesAndExit()
            }
        }
        // Auto-harvest knowledge from UMP logs for quick analysis
        KnowledgeAuto.start()
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
        let cHost = NSHostingView(rootView: EditorCanvas().environmentObject(vm2).environmentObject(AppState()))
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
    // Dashboard executor outputs for overlay rendering
    @Published var dashOutputs: [String:Payload] = [:]
    private var previewWindows: [String: NSWindow] = [:]

    // Open or focus a live preview window for a renderer node (panel.*)
    func openRendererPreview(id: String, vm: EditorVM) {
        if let win = previewWindows[id] {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let dash = dashboard[id] else { return }
        let view = RendererPreviewView(id: id, dash: dash, vm: vm).environmentObject(self)
        let host = NSHostingView(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 560, height: 360),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.contentView = host
        win.title = (dash.props["title"]) ?? (dashboard[id]?.kind.rawValue ?? id)
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        previewWindows[id] = win
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.previewWindows.removeValue(forKey: id) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeRendererPreview(id: String) {
        if let win = previewWindows[id] { win.close(); previewWindows.removeValue(forKey: id) }
    }
    // Templates (left panel library)
    private let templatesStore = InstrumentTemplatesStore()
    @Published var templates: [InstrumentTemplate] = []
    enum LeftMode: String, CaseIterable { case templates = "templates", openAPIs = "openAPIs", dashboard = "dashboard" }
    @Published var leftMode: LeftMode = .templates
    private let leftModeKey = "pb.leftMode.v1"
    func loadLeftMode() {
        if let raw = UserDefaults.standard.string(forKey: leftModeKey), let m = LeftMode(rawValue: raw) { leftMode = m } else { leftMode = .templates }
    }
    func saveLeftMode() { UserDefaults.standard.set(leftMode.rawValue, forKey: leftModeKey) }
    // Latest Teatro Guide artifact surfaced for preview/apply flows
    @Published var latestArtifactETag: String? = nil
    @Published var latestArtifactPath: URL? = nil
    // LLM usage preference (default ON); persisted
    @Published var useLLM: Bool = true
    @Published var llmModel: String = "gpt-4o-mini"
    @Published var gatewayURL: URL = URL(string: "http://127.0.0.1:8010")!
    enum GatewayStatus { case unknown, checking, ok, bad(String) }
    @Published var gatewayStatus: GatewayStatus = .unknown
    enum ServiceStatus: String { case unknown, checking, ok, bad }
    @Published var serviceHealth: [String: ServiceStatus] = [:]
    private let useLLMKey = "pb.useLLM.v1"
    private let llmModelKey = "pb.llmModel.v1"
    private let gatewayURLKey = "pb.gatewayURL.v1"
    let api: PatchBayAPI
    // Dashboard registry and servers metadata
    @Published var dashboard: [String:DashNode] = [:]
    @Published var serversMeta: [String:ServerMeta] = [:]
    private let dashboardKey = "pb.dashboard.v1"
    private let serversKey = "pb.serversMeta.v1"
    @Published var pendingEditNodeId: String? = nil
    init(api: PatchBayAPI = PatchBayClient()) {
        self.api = api
        self.templates = templatesStore.load()
        loadDashboard()
        loadServersMeta()
    }
    func loadUseLLM() {
        if UserDefaults.standard.object(forKey: useLLMKey) == nil {
            // Default to ON unless env explicitly disables
            let envOff = ProcessInfo.processInfo.environment["PATCHBAY_ASSISTANT_LLM"] == "0"
            useLLM = !envOff
        } else {
            useLLM = UserDefaults.standard.bool(forKey: useLLMKey)
        }
    }
    func saveUseLLM() { UserDefaults.standard.set(useLLM, forKey: useLLMKey) }
    func loadLLMModel() {
        if let s = UserDefaults.standard.string(forKey: llmModelKey), !s.isEmpty {
            llmModel = s
            return
        }
        if let fromEnv = ProcessInfo.processInfo.environment["GATEWAY_MODEL"], !fromEnv.isEmpty {
            llmModel = fromEnv
        }
    }
    func saveLLMModel() { UserDefaults.standard.set(llmModel, forKey: llmModelKey) }
    func loadGatewayURL() {
        if let s = UserDefaults.standard.string(forKey: gatewayURLKey), let u = URL(string: s) { gatewayURL = u; return }
        if let s = ProcessInfo.processInfo.environment["GATEWAY_URL"], let u = URL(string: s) { gatewayURL = u }
    }
    func saveGatewayURL() { UserDefaults.standard.set(gatewayURL.absoluteString, forKey: gatewayURLKey) }
    func checkGateway() async {
        await MainActor.run { gatewayStatus = .checking }
        var url = normalizedGatewayBase()
        url.append(path: "/openapi.yaml")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                await MainActor.run { gatewayStatus = .ok }
            } else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run { gatewayStatus = .bad("status \(code)") }
            }
        } catch {
            await MainActor.run { gatewayStatus = .bad(error.localizedDescription) }
        }
    }
    private func normalizedGatewayBaseIfAvailable(envURL: URL?) -> URL {
        if let u = envURL { self.gatewayURL = u }
        return normalizedGatewayBase()
    }

    @MainActor
    func checkServicesHealth(vm: EditorVM) async {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let root = cwd.appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
        let discovery = ServiceDiscovery(openAPIRoot: root)
        let services = (try? discovery.loadServices()) ?? []
        func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") }
        let byNode: [(PBNode, ServiceDescriptor?)] = vm.nodes.map { n in
            let m = services.first { sd in
                let t = norm(sd.title)
                let idn = norm(n.title ?? n.id)
                return t.contains(idn) || idn.contains(t)
            }
            return (n, m)
        }
        // Mark checking
        for (n, _) in byNode { serviceHealth[n.id] = .checking }
        // Probe concurrently
        await withTaskGroup(of: (String, ServiceStatus).self) { group in
            for (n, svc) in byNode {
                group.addTask {
                    guard let svc else { return (n.id, .unknown) }
                    let base = svc.servers.first ?? URL(string: "http://127.0.0.1:\(svc.port)")!
                    var url = base
                    // Normalize base (strip /api/v1), then choose a healthish path
                    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
                    let path = comps.path
                    if path.hasSuffix("/api/v1") { comps.path = String(path.dropLast("/api/v1".count)) }
                    if path.hasSuffix("/v1") { comps.path = String(path.dropLast("/v1".count)) }
                    url = comps.url ?? base
                    let healthPath = svc.healthPaths.first ?? "/health"
                    url.append(path: healthPath)
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    do {
                        let (_, resp) = try await URLSession.shared.data(for: req)
                        if let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                            return (n.id, .ok)
                        } else {
                            return (n.id, .bad)
                        }
                    } catch {
                        return (n.id, .bad)
                    }
                }
            }
            for await (id, st) in group { serviceHealth[id] = st }
        }
    }

    /// Returns a sanitized base URL without path suffixes like "/api/v1" or trailing slashes.
    func normalizedGatewayBase() -> URL {
        var url = gatewayURL
        // Strip common suffixes like /api/v1 or /v1
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        let path = comps.path
        let trimmed: String = {
            if path.hasSuffix("/api/v1") { return String(path.dropLast("/api/v1".count)) }
            if path.hasSuffix("/v1") { return String(path.dropLast("/v1".count)) }
            return path
        }()
        comps.path = trimmed
        if let u = comps.url { url = u }
        // Remove trailing slash
        if url.absoluteString.hasSuffix("/") {
            let s = String(url.absoluteString.dropLast())
            if let u = URL(string: s) { url = u }
        }
        return url
    }
    func refresh() async {
        if let list = try? await api.listInstruments() { instruments = list }
    }
    func refreshArtifacts() {
        // Scan .fountain/artifacts for newest response + etag pair (best-effort)
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let art = cwd.appendingPathComponent(".fountain/artifacts", isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: art, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        // Prefer teatro-guide.*.response, fall back to any *.response
        let candidates = items.filter { $0.lastPathComponent.hasSuffix(".response") }
        guard !candidates.isEmpty else { return }
        let sorted = candidates.sorted { (a, b) -> Bool in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        if let newest = sorted.first {
            latestArtifactPath = newest
            // Try sibling .etag
            let etagURL = newest.deletingPathExtension().appendingPathExtension("etag")
            if let etag = try? String(contentsOf: etagURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
                latestArtifactETag = etag
            } else {
                latestArtifactETag = nil
            }
        }
    }
    func openLatestArtifact() {
        guard let url = latestArtifactPath else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Dashboard registry
    func registerDashNode(id: String, kind: DashKind, props: [String:String]) {
        dashboard[id] = DashNode(id: id, kind: kind, props: props)
        saveDashboard()
    }
    func updateDashProps(id: String, props: [String:String]) {
        guard var n = dashboard[id] else { return }
        n.props = props
        dashboard[id] = n
        saveDashboard()
    }
    func removeDashNode(id: String) {
        dashboard.removeValue(forKey: id)
        saveDashboard()
    }
    private func loadDashboard() {
        if let data = UserDefaults.standard.data(forKey: dashboardKey), let map = try? JSONDecoder().decode([String:DashNode].self, from: data) {
            dashboard = map
        }
    }
    private func saveDashboard() {
        if let data = try? JSONEncoder().encode(dashboard) { UserDefaults.standard.set(data, forKey: dashboardKey) }
    }

    // MARK: - Servers metadata
    func registerServerNode(id: String, meta: ServerMeta) {
        serversMeta[id] = meta
        saveServersMeta()
    }
    func removeServerNode(id: String) {
        serversMeta.removeValue(forKey: id)
        saveServersMeta()
    }
    private func loadServersMeta() {
        if let data = UserDefaults.standard.data(forKey: serversKey), let map = try? JSONDecoder().decode([String:ServerMeta].self, from: data) {
            serversMeta = map
        }
    }
    private func saveServersMeta() {
        if let data = try? JSONEncoder().encode(serversMeta) { UserDefaults.standard.set(data, forKey: serversKey) }
    }

    // MARK: - Monitor (Prometheus removed)
    func clearCanvas(vm: EditorVM) {
        vm.nodes.removeAll(); vm.edges.removeAll(); vm.selection = nil; vm.selected.removeAll()
    }
    func applyLatestArtifactToCanvas(vm: EditorVM) async -> String {
        guard let url = latestArtifactPath else { return "No artifact found." }
        do {
            let data = try Data(contentsOf: url)
            // Attempt to decode a GraphDoc from the artifact. If it succeeds, reflect it locally on the canvas.
            let doc = try JSONDecoder().decode(Components.Schemas.GraphDoc.self, from: data)
            await MainActor.run {
                // Clear and rebuild nodes from instruments
                vm.nodes.removeAll()
                vm.edges.removeAll()
                for inst in doc.instruments {
                    // Reuse existing helper to map instrument → node + default ports
                    let id = inst.id
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
                    if inst.identity.hasUMPInput == true { vm.addPort(to: id, side: .left, dir: .input, id: "umpIn", type: "ump") }
                    if inst.identity.hasUMPOutput == true { vm.addPort(to: id, side: .right, dir: .output, id: "umpOut", type: "ump") }
                    vm.addPort(to: id, side: .left, dir: .input, id: "in", type: "data")
                    vm.addPort(to: id, side: .right, dir: .output, id: "out", type: "data")
                }
                // Build visual links. For property links, route out→in; for UMP, route umpOut→umpIn.
                for link in doc.links {
                    switch link.kind {
                    case .property:
                        if let f = link.property?.from, let t = link.property?.to {
                            let fromId = String((f.split(separator: ".").first) ?? "")
                            let toId = String((t.split(separator: ".").first) ?? "")
                            vm.edges.append(PBEdge(from: "\(fromId).out", to: "\(toId).in"))
                        }
                    case .ump:
                        if let to = link.ump?.to {
                            let toId = String((to.split(separator: ".").first) ?? "")
                            // Heuristic: link from a virtual MIDI source "midiIn" if present, else no-op
                            if vm.nodes.contains(where: { $0.id == "midiIn" }) {
                                vm.edges.append(PBEdge(from: "midiIn.umpOut", to: "\(toId).umpIn"))
                            }
                        }
                    }
                }
            }
            addLog(action: "apply-artifact", detail: latestArtifactETag ?? url.lastPathComponent, diff: "nodes=\(vm.nodes.count), links=\(vm.edges.count)")
            return "Applied artifact to canvas."
        } catch {
            return "Artifact is not a GraphDoc (or failed to parse)."
        }
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

    // Build an OpenAPI service network on the canvas from curated specs
    @MainActor
    func switchToOpenAPICuration(into vm: EditorVM, grid: Int = 24) {
        leftMode = .openAPIs
        saveLeftMode()
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let root = cwd.appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
        let discovery = ServiceDiscovery(openAPIRoot: root)
        guard let services = try? discovery.loadServices(), !services.isEmpty else {
            chat.append(.init(role: "assistant", text: "OpenAPI Curation: no specs found under \(root.path)"))
            return
        }
        vm.nodes.removeAll(); vm.edges.removeAll(); vm.grid = max(4, grid)
        // Layout services in a grid; stable order by file name
        let sorted = services.sorted { $0.fileName < $1.fileName }
        let colW = vm.grid * 14
        let rowH = vm.grid * 10
        var col = 0, row = 0
        func norm(_ s: String) -> String {
            let lowered = s.lowercased()
            let allowed = lowered.map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
            return String(allowed).replacingOccurrences(of: "--", with: "-")
        }
        for svc in sorted {
            let idBase = svc.binaryName ?? svc.title
            let id = norm(idBase)
            let x = vm.grid * 4 + col * colW
            let y = vm.grid * 4 + row * rowH
            let node = PBNode(
                id: id,
                title: svc.title,
                x: x,
                y: y,
                w: 240,
                h: 120,
                ports: canonicalSortPorts([
                    .init(id: "in", side: .left, dir: .input, type: "data"),
                    .init(id: "out", side: .right, dir: .output, type: "data")
                ])
            )
            vm.nodes.append(node)
            col += 1
            if col >= 5 { col = 0; row += 1 }
        }
        // Simple backbone: gateway -> all; planner -> function-caller; tools-factory -> tool-server
        func id(_ name: String) -> String? {
            let lowered = name.lowercased()
            return vm.nodes.first(where: { ($0.id == lowered) || ($0.title?.lowercased() == lowered) || $0.id.contains(lowered) })?.id
        }
        if let g = id("gateway") {
            for n in vm.nodes.map({ $0.id }) where n != g { _ = vm.ensureEdge(from: (g, "out"), to: (n, "in")) }
        }
        if let p = id("planner"), let f = id("function-caller") { _ = vm.ensureEdge(from: (p, "out"), to: (f, "in")) }
        if let t = id("tools-factory"), let s = id("tool-server") { _ = vm.ensureEdge(from: (t, "out"), to: (s, "in")) }
        chat.append(.init(role: "assistant", text: "Switched to corpus ‘OpenAPI Curation’. Placed \(vm.nodes.count) services."))
    }

    // Build a network reflecting only services that are actually reachable (true running state)
    @MainActor
    func switchToOpenAPIRunning(into vm: EditorVM, grid: Int = 24) async {
        leftMode = .openAPIs
        saveLeftMode()
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let root = cwd.appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
        let discovery = ServiceDiscovery(openAPIRoot: root)
        guard let services = try? discovery.loadServices(), !services.isEmpty else {
            chat.append(.init(role: "assistant", text: "OpenAPI Curation: no specs found under \(root.path)"))
            return
        }
        // Probe each service for readiness (/openapi.yaml or /health)
        struct ProbeResult { let svc: ServiceDescriptor; let ok: Bool }
        var results: [ProbeResult] = []
        await withTaskGroup(of: ProbeResult.self) { group in
            for svc in services {
                group.addTask {
                    let base = svc.servers.first ?? URL(string: "http://127.0.0.1:\(svc.port)")!
                    // Normalize base (strip common suffixes)
                    var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
                    let path = comps.path
                    if path.hasSuffix("/api/v1") { comps.path = String(path.dropLast("/api/v1".count)) }
                    if path.hasSuffix("/v1") { comps.path = String(path.dropLast("/v1".count)) }
                    let url = comps.url ?? base
                    // Try /openapi.yaml then /health
                    var req = URLRequest(url: url.appending(path: "/openapi.yaml")); req.httpMethod = "GET"
                    do {
                        let (_, resp) = try await URLSession.shared.data(for: req)
                        let ok = (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
                        if ok { return ProbeResult(svc: svc, ok: true) }
                    } catch { }
                    req = URLRequest(url: url.appending(path: "/health")); req.httpMethod = "GET"
                    do {
                        let (_, resp) = try await URLSession.shared.data(for: req)
                        let ok = (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
                        return ProbeResult(svc: svc, ok: ok)
                    } catch {
                        return ProbeResult(svc: svc, ok: false)
                    }
                }
            }
            for await r in group { results.append(r) }
        }
        let healthy = results.filter { $0.ok }.map { $0.svc }
        vm.nodes.removeAll(); vm.edges.removeAll(); vm.grid = max(4, grid)
        // Layout
        let sorted = healthy.sorted { $0.fileName < $1.fileName }
        let colW = vm.grid * 14
        let rowH = vm.grid * 10
        var col = 0, row = 0
        func norm(_ s: String) -> String {
            let lowered = s.lowercased()
            let allowed = lowered.map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
            return String(allowed).replacingOccurrences(of: "--", with: "-")
        }
        for svc in sorted {
            let idBase = svc.binaryName ?? svc.title
            let id = norm(idBase)
            let x = vm.grid * 4 + col * colW
            let y = vm.grid * 4 + row * rowH
            let node = PBNode(
                id: id,
                title: svc.title,
                x: x,
                y: y,
                w: 240,
                h: 120,
                ports: canonicalSortPorts([
                    .init(id: "in", side: .left, dir: .input, type: "data"),
                    .init(id: "out", side: .right, dir: .output, type: "data")
                ])
            )
            vm.nodes.append(node)
            col += 1
            if col >= 5 { col = 0; row += 1 }
        }
        // Edges reflecting baseline wiring but only among reachable nodes
        func has(_ name: String) -> String? {
            let lowered = name.lowercased()
            return vm.nodes.first(where: { ($0.id == lowered) || ($0.title?.lowercased() == lowered) || $0.id.contains(lowered) })?.id
        }
        if let g = has("gateway") {
            for n in vm.nodes.map({ $0.id }) where n != g { _ = vm.ensureEdge(from: (g, "out"), to: (n, "in")) }
        }
        if let p = has("planner"), let f = has("function-caller") { _ = vm.ensureEdge(from: (p, "out"), to: (f, "in")) }
        if let t = has("tools-factory"), let s = has("tool-server") { _ = vm.ensureEdge(from: (t, "out"), to: (s, "in")) }
        chat.append(.init(role: "assistant", text: "Detected \(vm.nodes.count) running services; canvas reflects live state."))
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
        // Selection/service-aware Q&A for what you see on the canvas
        func normalize(_ s: String) -> String { s.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") }
        func servicesFromCuration() -> [ServiceDescriptor] {
            let fm = FileManager.default
            let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
            let root = cwd.appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
            let discovery = ServiceDiscovery(openAPIRoot: root)
            return (try? discovery.loadServices()) ?? []
        }
        func describe(node n: PBNode, services: [ServiceDescriptor]) -> String {
            let inNeighbors = vm.edges.filter { $0.to.hasPrefix(n.id+".") }.compactMap { $0.from.split(separator: ".").first }.map(String.init)
            let outNeighbors = vm.edges.filter { $0.from.hasPrefix(n.id+".") }.compactMap { $0.to.split(separator: ".").first }.map(String.init)
            let svc = services.first { sd in
                let t = normalize(sd.title)
                let idn = normalize(n.title ?? n.id)
                return t.contains(idn) || idn.contains(t)
            }
            var lines: [String] = []
            lines.append("Service: \(n.title ?? n.id) (id=\(n.id))")
            if let s = svc {
                lines.append("Port: \(s.port)")
                if !s.servers.isEmpty { lines.append("Servers: \(s.servers.map{ $0.absoluteString }.joined(separator: ", "))") }
                if !s.healthPaths.isEmpty { lines.append("Health: \(s.healthPaths.joined(separator: ", "))") }
                if !s.capabilityPaths.isEmpty { lines.append("Capabilities: \(s.capabilityPaths.joined(separator: ", "))") }
                lines.append("Spec: openapi/v1/\(s.fileName)")
            }
            if !inNeighbors.isEmpty { lines.append("Incoming from: \(inNeighbors.joined(separator: ", "))") }
            if !outNeighbors.isEmpty { lines.append("Outgoing to: \(outNeighbors.joined(separator: ", "))") }
            return lines.joined(separator: "\n")
        }
        let q = question.lowercased()
        if q.contains("what") || q.contains("describe") || q.contains("about") || q.contains("info") {
            // Prefer selection if present
            if let sel = vm.selection, let node = vm.node(by: sel) {
                let text = describe(node: node, services: servicesFromCuration())
                chat.append(.init(role: "assistant", text: text))
                return
            }
            // Fuzzy match query → node title/id
            let normQ = normalize(question)
            if let node = vm.nodes.first(where: { let t = normalize($0.title ?? $0.id); return normQ.contains(t) || t.contains(normQ) }) {
                let text = describe(node: node, services: servicesFromCuration())
                chat.append(.init(role: "assistant", text: text))
                return
            }
        }
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
        // LLM Assistant via Gateway (default ON); toggle via state.useLLM
        if useLLM {
            // Prefer user-configured gateway URL; fall back to env only when unset
            let envURL = ProcessInfo.processInfo.environment["GATEWAY_URL"].flatMap(URL.init(string:))
            let base = normalizedGatewayBaseIfAvailable(envURL: envURL)
            let tokenProvider: GatewayChatClient.TokenProvider = { ProcessInfo.processInfo.environment["GATEWAY_TOKEN"] }
            let client = GatewayChatClient(baseURL: base, tokenProvider: tokenProvider)
            let model = self.llmModel.isEmpty ? (ProcessInfo.processInfo.environment["GATEWAY_MODEL"] ?? "gpt-4o-mini") : self.llmModel
            let req = GroundedPromptBuilder.makeChatRequest(model: model, userQuestion: question, nodes: vm.nodes, edges: vm.edges)
            do {
                var accum = ""
                var finalResponse: GatewayChatResponse? = nil
                var assistantIndex: Int? = nil
                for try await chunk in client.stream(request: req, preferStreaming: true) {
                    if !chunk.text.isEmpty { accum += chunk.text }
                    await MainActor.run {
                        if assistantIndex == nil { chat.append(.init(role: "assistant", text: "")); assistantIndex = chat.count - 1 }
                        if let i = assistantIndex { chat[i] = .init(role: "assistant", text: accum) }
                    }
                    if chunk.isFinal { finalResponse = chunk.response }
                }
                if let resp = finalResponse {
                    let actions = OpenAPIActionParser.parse(from: resp.functionCall)
                    if !actions.isEmpty {
                        let applied = await execute(actions: actions, vm: vm)
                        chat.append(.init(role: "assistant", text: applied))
                        return
                    }
                }
                return
            } catch {
                chat.append(.init(role: "assistant", text: "LLM error: \(error.localizedDescription). Falling back…"))
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

    // MARK: - Templates API
    func renameTemplate(id: String, to: String) { templatesStore.rename(id: id, to: to, in: &templates) }
    func toggleHiddenTemplate(id: String) { templatesStore.toggleHidden(id: id, in: &templates) }
    func moveTemplates(fromOffsets: IndexSet, toOffset: Int) { templatesStore.move(fromOffsets: fromOffsets, toOffset: toOffset, items: &templates) }
    func resetTemplates() { templates = templatesStore.reset() }
    func restoreAllTemplates() {
        var items = templates
        var changed = false
        for i in items.indices where items[i].hidden {
            items[i].hidden = false
            changed = true
        }
        if changed { templates = items; templatesStore.save(templates) }
    }

    // Corpus quick overview (computed from current state as a fallback)
    func corpusOverviewLine() -> String {
        let tri = instruments.filter { $0.kind.rawValue == "mvk.triangle" }.count
        let quad = instruments.filter { $0.kind.rawValue == "mvk.quad" }.count
        let chat = instruments.filter { $0.kind.rawValue == "audiotalk.chat" }.count
        let core = instruments.filter { $0.kind.rawValue == "external.coremidi" }.count
        let totalI = instruments.count
        let prop = links.filter { $0.kind == .property }.count
        let ump = links.filter { $0.kind == .ump }.count
        let totalL = links.count
        return "Instruments: \(totalI) [tri \(tri), quad \(quad), chat \(chat), coremidi \(core)] · Links: \(totalL) [property \(prop), ump \(ump)]"
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
    @State private var showDashEditor: Bool = false
    init(state: AppState = AppState()) { _state = StateObject(wrappedValue: state) }
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.automatic)) {
            // Left: Template Library
            TemplateLibraryView()
                .environmentObject(state)
                .environmentObject(vm)
                .navigationTitle("Templates")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            // Center: Canvas only (right pane removed)
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
                HStack(spacing: 0) {
                    MetalCanvasHost()
                        .environmentObject(vm)
                        .environmentObject(state)
                        .background(Color(NSColor.textBackgroundColor))
                        .onDrop(of: [UTType.json, UTType.text], isTargeted: .constant(false)) { providers, location in
                            handleDrop(providers: providers, location: location)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Divider()
                        Toggle("Show Baseline Index", isOn: $vm.showBaselineIndex)
                        Toggle("Always show (all stages)", isOn: $vm.alwaysShowBaselineIndex)
                            .disabled(!vm.showBaselineIndex)
                        Toggle("Use 1‑based indices", isOn: $vm.baselineIndexOneBased)
                            .disabled(!vm.showBaselineIndex)
                    }
                    // Knowledge/Monitor menu: clear canvas, harvest logs, open knowledge folder
                    Menu("Knowledge") {
                        Button("Harvest Logs to Knowledge") {
                            if let url = try? StoryLogHarvester.harvestAll() { NSWorkspace.shared.open(url) }
                        }
                        Button("Open Knowledge Folder") { StoryLogHarvester.openKnowledgeFolder() }
                        Button("Export Replay Frames from Log…") {
                            let panel = NSOpenPanel()
                            if #available(macOS 12.0, *) {
                                panel.allowedContentTypes = [UTType(filenameExtension: "ndjson")!]
                            } else {
                                panel.allowedFileTypes = ["ndjson"]
                            }
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = false
                            panel.title = "Choose a .ndjson story log"
                            if panel.runModal() == .OK, let url = panel.url {
                                Task { await ReplayExporter.exportFrames(from: url) }
                            }
                        }
                        Button("Export Replay Movie from Log (auto)…") {
                            let open = NSOpenPanel()
                            if #available(macOS 12.0, *) {
                                open.allowedContentTypes = [UTType(filenameExtension: "ndjson")!]
                            } else {
                                open.allowedFileTypes = ["ndjson"]
                            }
                            open.allowsMultipleSelection = false
                            open.canChooseDirectories = false
                            open.title = "Choose a .ndjson story log"
                            if open.runModal() == .OK, let logURL = open.url {
                                let fm = FileManager.default
                                let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
                                let outRoot = cwd.appendingPathComponent(".fountain/artifacts/replay", isDirectory: true)
                                try? fm.createDirectory(at: outRoot, withIntermediateDirectories: true)
                                let base = logURL.deletingPathExtension().lastPathComponent
                                let outDir = outRoot.appendingPathComponent(base, isDirectory: true)
                                try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
                                let outURL = outDir.appendingPathComponent("\(base).mov")
                                Task {
                                    try? await ReplayMovieExporter.exportMovie(from: logURL, to: outURL, width: 1440, height: 900, fps: 10)
                                    NSWorkspace.shared.open(outDir)
                                }
                            }
                        }
                        Divider()
                        Button("Clear Canvas") { state.clearCanvas(vm: vm) }
                    }
                    // Left Pane menu removed: mode switching is self-contained within the left pane
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
            state.refreshArtifacts()
            state.loadLeftMode()
            state.loadUseLLM()
            state.loadLLMModel()
            state.loadGatewayURL()
            if vm.nodes.isEmpty { state.clearCanvas(vm: vm) }
        }
        .onChange(of: state.pendingEditNodeId) { _, new in showDashEditor = (new != nil) }
        .sheet(isPresented: $showDashEditor) {
            if let id = state.pendingEditNodeId, let dash = state.dashboard[id] {
                DashEditSheet(state: state, vm: vm, id: id, dash: dash) { state.pendingEditNodeId = nil }
            }
        }
        .environmentObject(vm)
    }

    // Compute the next Stage name from the canvas only (ignores stale persisted entries).
    private func nextStageTitle() -> String {
        func parseStageIndex(_ title: String?) -> Int? {
            guard let s = title else { return nil }
            let t = s.trimmingCharacters(in: .whitespaces)
            guard t.lowercased().hasPrefix("stage ") else { return nil }
            return Int(t.dropFirst("stage ".count))
        }
        var used: Set<Int> = []
        for n in vm.nodes where state.dashboard[n.id]?.kind == .stageA4 {
            if let i = parseStageIndex(state.dashboard[n.id]?.props["title"]) ?? parseStageIndex(n.title) { used.insert(i) }
        }
        var i = 1
        while used.contains(i) { i += 1 }
        return "Stage \(i)"
    }

    // Shared: compute baseline count from props
    private func stageBaselineCount(from props: [String:String]) -> Int {
        let page = props["page"]?.lowercased() ?? "a4"
        let height: Double = (page == "letter") ? 792.0 : 842.0
        let baseline = Double(props["baseline"] ?? "12") ?? 12.0
        let mparts = (props["margins"] ?? "18,18,18,18").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let top = mparts.count == 4 ? mparts[0] : 18.0
        let bottom = mparts.count == 4 ? mparts[2] : 18.0
        let usable = max(0.0, height - top - bottom)
        return max(1, Int(floor(usable / max(1.0, baseline))))
    }

    // Canonical Stage page size in points
    private func stagePageSize(_ props: [String:String]) -> (Int, Int) {
        let page = props["page"]?.lowercased() ?? "a4"
        if page == "letter" { return (612, 792) } // 8.5x11in at 72dpi
        return (595, 842) // A4 at 72dpi
    }

    private func buildPrometheusExample() { /* removed */ }

    private func seedWelcomeScene() { /* removed in chat‑only startup */ }

    private func handleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        // 1) Stage move payload (text): "moveStage:<id>"
        if let tp = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            _ = tp.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
                guard let data = data, let s = String(data: data, encoding: .utf8) else { return }
                if s.hasPrefix("moveStage:") {
                    let id = String(s.dropFirst("moveStage:".count))
                    Task { @MainActor in
                        let z = max(0.0001, vm.zoom)
                        let docX = Int((location.x / z) - vm.translation.x)
                        let docY = Int((location.y / z) - vm.translation.y)
                        let g = max(1, vm.grid)
                        let snap: (Int) -> Int = { ((($0 + g/2) / g) * g) }
                        if let i = vm.nodeIndex(by: id) {
                            vm.nodes[i].x = snap(docX)
                            vm.nodes[i].y = snap(docY)
                            vm.selection = id; vm.selected = [id]
                        }
                    }
                    return
                }
            }
        }
        // 2) Node creation payloads (json)
        guard let prov = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.json.identifier) }) else { return false }
        _ = prov.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
            guard let data = data else { return }
            struct TemplatePayload: Codable { let templateId: String?; let kind: String?; let title: String?; let w: Int?; let h: Int? }
            struct FlowPayload: Codable { let flowKind: String? }
            struct ServerPayload: Codable { let serverId: String?; let title: String?; let port: Int?; let spec: String? }
            struct DashPayload: Codable { let dashKind: String?; let props: [String:String]? }
            let decoder = JSONDecoder()
            if let sp = try? decoder.decode(ServerPayload.self, from: data), let sid = sp.serverId, let title = sp.title, let port = sp.port {
                Task { @MainActor in
                    let z = max(0.0001, vm.zoom)
                    let docX = Int((location.x / z) - vm.translation.x)
                    let docY = Int((location.y / z) - vm.translation.y)
                    let g = max(1, vm.grid)
                    let snap: (Int) -> Int = { ((($0 + g/2) / g) * g) }
                    let id = normalizeServerId(sid)
                    let node = PBNode(id: id, title: title, x: snap(docX), y: snap(docY), w: 240, h: 120, ports: canonicalSortPorts([
                        .init(id: "in", side: .left, dir: .input, type: "data"), .init(id: "out", side: .right, dir: .output, type: "data")
                    ]))
                    vm.nodes.append(node)
                    state.registerServerNode(id: id, meta: ServerMeta(serviceId: id, title: title, port: port, specRelativePath: sp.spec ?? ""))
                    vm.selection = id; vm.selected = [id]
                }
                return
            }
            if let dp = try? decoder.decode(DashPayload.self, from: data), let kindRaw = dp.dashKind {
                Task { @MainActor in
                    let z = max(0.0001, vm.zoom)
                    let docX = Int((location.x / z) - vm.translation.x)
                    let docY = Int((location.y / z) - vm.translation.y)
                    let g = max(1, vm.grid)
                    let snap: (Int) -> Int = { ((($0 + g/2) / g) * g) }
                    let kind = DashKind(rawValue: kindRaw) ?? .transform
                    createDashNode(kind: kind, props: dp.props ?? [:], x: snap(docX), y: snap(docY))
                }
                return
            }
            if let fp = try? decoder.decode(FlowPayload.self, from: data), let flowKind = fp.flowKind {
                Task { @MainActor in
                    let kind = FlowNodeKind(rawValue: flowKind) ?? .analyzer
                    let z = max(0.0001, vm.zoom)
                    let docX = Int((location.x / z) - vm.translation.x)
                    let docY = Int((location.y / z) - vm.translation.y)
                    let g = max(1, vm.grid)
                    let snap: (Int) -> Int = { ((($0 + g/2) / g) * g) }
                    addFlowNode(kind: kind, title: flowKind, x: snap(docX), y: snap(docY))
                    NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type":"node.add", "kind": flowKind, "x": snap(docX), "y": snap(docY)])
                }
                return
            }
            guard let p = try? decoder.decode(TemplatePayload.self, from: data), let kindStr = p.kind, let title = p.title, let w = p.w, let h = p.h else { return }
            Task { @MainActor in
                let kind = Components.Schemas.InstrumentKind(rawValue: kindStr) ?? .init(rawValue: kindStr)!
                let base = baseForKind(kindStr, title: title)
                let id = nextId(base: base)
                // Convert drop location (view coords) → doc coords, snap to grid
                let z = max(0.0001, vm.zoom)
                let docX = Int((location.x / z) - vm.translation.x)
                let docY = Int((location.y / z) - vm.translation.y)
                let g = max(1, vm.grid)
                let snap: (Int) -> Int = { ((($0 + g/2) / g) * g) }
                let x = snap(docX)
                let y = snap(docY)
                if let c = state.api as? PatchBayClient {
                    do {
                        if let inst = try await c.createInstrument(id: id, kind: kind, title: title, x: x, y: y, w: w, h: h) {
                            var node = PBNode(id: inst.id, title: inst.title, x: inst.x, y: inst.y, w: inst.w, h: inst.h, ports: [])
                            node.ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
                            node.ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
                            if inst.identity.hasUMPInput == true { node.ports.append(.init(id: "umpIn", side: .left, dir: .input, type: "ump")) }
                            if inst.identity.hasUMPOutput == true { node.ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump")) }
                            vm.nodes.append(node)
                            vm.selection = inst.id
                            vm.selected = [inst.id]
                            NotificationCenter.default.post(name: .MetalCanvasMIDIActivity, object: nil, userInfo: ["type":"node.add", "id": inst.id, "x": node.x, "y": node.y])
                        }
                    } catch { }
                }
            }
        }
        return true
    }

    private func baseForKind(_ kind: String, title: String) -> String {
        if kind == "audiotalk.chat" { return "chat" }
        if kind == "mvk.triangle" { return "tri" }
        if kind == "mvk.quad" { return "quad" }
        if kind == "external.coremidi" { return "midi" }
        let cleaned = title.lowercased().replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty ? "inst" : cleaned
    }

    private func nextId(base: String) -> String {
        var n = 1
        let existing = Set(vm.nodes.map { $0.id })
        var candidate = "\(base)_\(n)"
        while existing.contains(candidate) { n += 1; candidate = "\(base)_\(n)" }
        return candidate
    }

    private func createDashNode(kind: DashKind, props: [String:String], x: Int, y: Int) {
        let base: String = {
            switch kind {
            case .datasource: return "ds"
            case .query: return "q"
            case .transform: return "xf"
            case .aggregator: return "agg"
            case .topN: return "top"
            case .threshold: return "thr"
            case .panelLine: return "p"
            case .panelStat: return "ps"
            case .panelTable: return "pt"
            case .stageA4: return "stage"
            case .replayPlayer: return "replay"
            case .adapterFountain: return "fxf"
            case .adapterScoreKit: return "fxs"
            }
        }()
        let id = nextId(base: base)
        var ports: [PBPort] = []
        // Ports by kind
        switch kind {
        case .datasource:
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
        case .panelLine:
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
        case .panelStat, .panelTable:
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
        case .stageA4:
            // Stage capacity maps to baseline count
            let page = props["page"]?.lowercased() ?? "a4"
            let height: Double = (page == "letter") ? 792.0 : 842.0
            let baseline = Double(props["baseline"] ?? "12") ?? 12.0
            let mparts = (props["margins"] ?? "18,18,18,18").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let top = mparts.count == 4 ? mparts[0] : 18.0
            let bottom = mparts.count == 4 ? mparts[2] : 18.0
            let usable = max(0.0, height - top - bottom)
            let count = max(1, Int(floor(usable / max(1.0, baseline))))
            for i in 0..<count { ports.append(.init(id: "in\(i)", side: .left, dir: .input, type: "view")) }
        case .adapterFountain, .adapterScoreKit:
            ports.append(.init(id: "out", side: .right, dir: .output, type: "view"))
        default:
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
        }
        // Stage sizing uses canonical page size so node equals page
        let stageSize: (Int, Int) = stagePageSize(props)
        let node = PBNode(id: id, title: {
            switch kind {
            case .datasource: return "prom.datasource"
            case .query: return "prom.query"
            case .transform: return "prom.transform"
            case .aggregator: return "prom.aggregator"
            case .topN: return "prom.topN"
            case .threshold: return "prom.threshold"
            case .panelLine: return "prom.panel.line"
            case .panelStat: return "prom.panel.stat"
            case .panelTable: return "prom.panel.table"
            case .stageA4: return "stage.a4"
            case .replayPlayer: return "replay.player"
            case .adapterFountain: return "adapter.fountain→teatro"
            case .adapterScoreKit: return "adapter.scorekit→teatro"
            }
        }(), x: x, y: y,
           w: (kind == .stageA4 ? stageSize.0 : 260),
           h: (kind == .stageA4 ? stageSize.1 : (kind == .panelLine ? 200 : (kind == .panelStat ? 140 : (kind == .panelTable ? 200 : (kind == .replayPlayer ? 180 : 140))))),
           ports: canonicalSortPorts(ports))
        vm.nodes.append(node)
        var propsToSave = props
        if kind == .stageA4 {
            // Use the same numbering logic here
            func parseStageIndex(_ title: String?) -> Int? {
                guard let s = title else { return nil }
                let t = s.trimmingCharacters(in: .whitespaces)
                guard t.lowercased().hasPrefix("stage ") else { return nil }
                return Int(t.dropFirst("stage ".count))
            }
            var maxIdx = 0
            for (_, node) in state.dashboard where node.kind == .stageA4 { if let n = parseStageIndex(node.props["title"]) { maxIdx = max(maxIdx, n) } }
            for n in vm.nodes where state.dashboard[n.id]?.kind == .stageA4 { if let i = parseStageIndex(n.title) { maxIdx = max(maxIdx, i) } }
            let defaultTitle = "Stage \(maxIdx + 1)"
            let current = propsToSave["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if current == nil || current == "" || current == "The Stage" { propsToSave["title"] = defaultTitle }
            vm.setNodeTitle(id: id, title: propsToSave["title"] ?? defaultTitle)
        }
        state.registerDashNode(id: id, kind: kind, props: propsToSave)
        vm.selection = id; vm.selected = [id]
        autoWire(newId: id, kind: kind)
    }

    private func autoWire(newId: String, kind: DashKind) {
        func lastId(where pred: (String, DashKind) -> Bool) -> String? {
            let ids = vm.nodes.map { $0.id }
            for id in ids.reversed() {
                if let k = state.dashboard[id]?.kind, pred(id, k) { return id }
            }
            return nil
        }
        switch kind {
        case .query:
            if let ds = lastId(where: { _, k in k == .datasource }) { _ = vm.ensureEdge(from: (ds,"out"), to: (newId,"in")) }
        case .transform, .aggregator, .topN, .threshold:
            if let upstream = vm.selection ?? lastId(where: { _, k in k == .query || k == .transform }) { _ = vm.ensureEdge(from: (upstream,"out"), to: (newId,"in")) }
        case .panelLine:
            if let up = vm.selection ?? lastId(where: { _, k in k == .aggregator || k == .transform || k == .query }) { _ = vm.ensureEdge(from: (up,"out"), to: (newId,"in")) }
        case .panelStat:
            if let agg = lastId(where: { _, k in k == .aggregator }) { _ = vm.ensureEdge(from: (agg,"out"), to: (newId,"in")) }
        case .panelTable:
            if let top = lastId(where: { _, k in k == .topN }) { _ = vm.ensureEdge(from: (top,"out"), to: (newId,"in")) }
        case .stageA4:
            if let up = lastId(where: { _, k in k == .panelLine || k == .panelStat || k == .panelTable || k == .adapterFountain || k == .adapterScoreKit }) { _ = vm.ensureEdge(from: (up,"out"), to: (newId,"in0")) }
        case .replayPlayer:
            break
        case .adapterFountain, .adapterScoreKit:
            if let stage = lastId(where: { _, k in k == .stageA4 }) { _ = vm.ensureEdge(from: (newId,"out"), to: (stage,"in0")) }
        case .datasource:
            break
        }
    }

    private func addFlowNode(kind: FlowNodeKind, title: String, x: Int, y: Int) {
        let base: String = {
            switch kind {
            case .audioInput: return "audioIn"
            case .analyzer: return "analyzer"
            case .noteProcessor: return "noteProc"
            case .transportEndpoint: return "endpoint"
            }
        }()
        let id = nextId(base: base)
        var ports: [PBPort] = []
        switch kind {
        case .audioInput:
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
        case .analyzer:
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
        case .noteProcessor:
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
            ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump"))
        case .transportEndpoint:
            ports.append(.init(id: "ciIn", side: .left, dir: .input, type: "ci"))
            ports.append(.init(id: "ciOut", side: .right, dir: .output, type: "ci"))
            ports.append(.init(id: "umpIn", side: .left, dir: .input, type: "ump"))
            ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump"))
        }
        let node = PBNode(id: id, title: title, x: x, y: y, w: kind == .transportEndpoint ? 260 : 220, h: 120, ports: canonicalSortPorts(ports))
        vm.nodes.append(node)
        vm.selection = id
        vm.selected = [id]
    }
}

struct DashEditSheet: View {
    @ObservedObject var state: AppState
    @ObservedObject var vm: EditorVM
    let id: String
    let dash: DashNode
    var dismiss: () -> Void
    @State private var baseURL: String = "http://127.0.0.1:9090"
    @State private var promQL: String = ""
    @State private var rangeSeconds: String = "300"
    @State private var stepSeconds: String = "15"
    @State private var refreshSeconds: String = "10"
    @State private var title: String = ""
    @State private var sourcePath: String = ""
    // Replay player properties
    @State private var replayFPS: String = "10"
    @State private var replayPlaying: Bool = false
    @State private var replayFrame: String = "0"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Edit \(dash.kind.rawValue)").font(.title3).bold(); Spacer(); Button("Close") { dismiss() } }
            switch dash.kind {
            case .datasource:
                TextField("Base URL", text: $baseURL)
            case .query:
                TextField("PromQL", text: $promQL)
                HStack { TextField("Range (s)", text: $rangeSeconds); TextField("Step (s)", text: $stepSeconds); TextField("Refresh (s)", text: $refreshSeconds) }
            case .panelLine:
                TextField("Title", text: $title)
            case .transform:
                Text("Transform properties pending").foregroundStyle(.secondary)
            case .panelStat:
                Text("Stat panel properties pending").foregroundStyle(.secondary)
            case .panelTable:
                TextField("Title", text: $title)
            case .aggregator:
                TextField("Op (last/avg/min/max)", text: Binding(get: { dash.props["op"] ?? "avg" }, set: { _ in }))
            case .topN:
                TextField("N", text: Binding(get: { dash.props["n"] ?? "5" }, set: { _ in }))
            case .threshold:
                TextField("Threshold", text: Binding(get: { dash.props["threshold"] ?? "0" }, set: { _ in }))
            case .stageA4:
                TextField("Title", text: $title)
                HStack { TextField("Page (A4/Letter)", text: Binding(get: { dash.props["page"] ?? "A4" }, set: { _ in })); TextField("Baseline (pt)", text: Binding(get: { dash.props["baseline"] ?? "12" }, set: { _ in })) }
                TextField("Margins (t,l,b,r)", text: Binding(get: { dash.props["margins"] ?? "18,18,18,18" }, set: { _ in }))
            case .replayPlayer:
                TextField("Title", text: $title)
                HStack {
                    TextField("FPS", text: $replayFPS).frame(width: 80)
                    Toggle("Playing", isOn: $replayPlaying)
                }
                TextField("Frame Index", text: $replayFrame).frame(width: 140)
            case .adapterFountain, .adapterScoreKit:
                TextField("Source (file path)", text: $sourcePath)
            }
            HStack { Spacer(); Button("Save") { save(); dismiss() } }
        }
        .padding(14)
        .frame(minWidth: 480)
        .onAppear { load() }
    }
    private func load() {
        let p = dash.props
        baseURL = p["baseURL"] ?? baseURL
        promQL = p["promQL"] ?? promQL
        rangeSeconds = p["rangeSeconds"] ?? rangeSeconds
        stepSeconds = p["stepSeconds"] ?? stepSeconds
        refreshSeconds = p["refreshSeconds"] ?? refreshSeconds
        title = p["title"] ?? dash.kind.rawValue
        // Replay
        replayFPS = p["fps"] ?? replayFPS
        replayPlaying = (p["playing"] ?? "0") == "1"
        replayFrame = p["frame"] ?? replayFrame
        sourcePath = p["source"] ?? sourcePath
    }
    private func save() {
        var p = dash.props
        switch dash.kind {
        case .datasource:
            p["baseURL"] = baseURL
        case .query:
            p["promQL"] = promQL
            p["rangeSeconds"] = rangeSeconds
            p["stepSeconds"] = stepSeconds
            p["refreshSeconds"] = refreshSeconds
        case .panelLine:
            p["title"] = title
        case .stageA4:
            p["title"] = title
            vm.setNodeTitle(id: id, title: title)
            // Recompute baseline-derived ports and migrate edges
            reflowStagePorts(id: id, props: p)
        case .replayPlayer:
            p["title"] = title
            vm.setNodeTitle(id: id, title: title)
            p["fps"] = replayFPS
            p["playing"] = replayPlaying ? "1" : "0"
            p["frame"] = replayFrame
        case .adapterFountain, .adapterScoreKit:
            p["source"] = sourcePath
        default: break
        }
        state.updateDashProps(id: id, props: p)
    }

    private func reflowStagePorts(id: String, props: [String:String]) {
        guard let i = vm.nodeIndex(by: id) else { return }
        func stageBaselineCountLocal(_ props: [String:String]) -> Int {
            let page = props["page"]?.lowercased() ?? "a4"
            let height: Double = (page == "letter") ? 792.0 : 842.0
            let baseline = Double(props["baseline"] ?? "12") ?? 12.0
            let mparts = (props["margins"] ?? "18,18,18,18").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let top = mparts.count == 4 ? mparts[0] : 18.0
            let bottom = mparts.count == 4 ? mparts[2] : 18.0
            let usable = max(0.0, height - top - bottom)
            return max(1, Int(floor(usable / max(1.0, baseline))))
        }
        let newCount = stageBaselineCountLocal(props)
        let oldIn = vm.nodes[i].ports.filter { $0.dir == .input && $0.id.hasPrefix("in") }
        if oldIn.count == newCount { return }
        // Rebuild ports: inputs only (left)
        var ports: [PBPort] = []
        for k in 0..<newCount { ports.append(.init(id: "in\(k)", side: .left, dir: .input, type: "view")) }
        vm.nodes[i].ports = canonicalSortPorts(ports)
        // Resize node to canonical page size so page and node are one
        func stagePageSizeLocal(_ props: [String:String]) -> (Int, Int) {
            let page = props["page"]?.lowercased() ?? "a4"
            if page == "letter" { return (612, 792) }
            return (595, 842)
        }
        let sz = stagePageSizeLocal(props)
        vm.nodes[i].w = sz.0
        vm.nodes[i].h = sz.1
        // Migrate edges
        for eidx in 0..<vm.edges.count {
            var e = vm.edges[eidx]
            if e.to.hasPrefix(id + ".in") {
                if let idxStr = e.to.split(separator: ".").last?.dropFirst(2), let idx = Int(idxStr) {
                    let clamped = max(0, min(newCount - 1, idx))
                    e.to = id + ".in\(clamped)"
                    vm.edges[eidx] = e
                }
            }
        }
    }
}

// MARK: - Add Instrument UI

struct AddInstrumentToolbar: View {
    @ObservedObject var state: AppState
    @ObservedObject var vm: EditorVM
    @State private var showSheet: Bool = false
    var body: some View {
        Button {
            // Double activation to withstand Terminal launches
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [])
            if let w = NSApp.keyWindow ?? NSApp.windows.first { w.makeKeyAndOrderFront(nil) }
            showSheet = true
        } label: { Label("Add Instrument", systemImage: "plus") }
            .sheet(isPresented: $showSheet) { AddInstrumentSheet(state: state, vm: vm, dismiss: { showSheet = false }) }
            .help("Create an instrument on the PatchBay service and place it on the canvas")
    }
}

// MARK: - Template Library (left panel)
struct TemplateLibraryView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    var body: some View {
        List {
            Section(header: Text("Stage").font(.headline)) {
                DashNodeRow(title: "Add Stage (A4)", dashKind: .stageA4, defaultProps: ["title":"The Stage", "page":"A4", "margins":"18,18,18,18", "baseline":"12"]).environmentObject(state).environmentObject(vm)
            }
            Section(header: Text("Instruments").font(.headline)) {
                DashNodeRow(title: "Replay Player", dashKind: .replayPlayer, defaultProps: ["title":"Replay", "fps":"10", "playing":"0", "frame":"0"]).environmentObject(state).environmentObject(vm)
            }
            // Existing stages on canvas
            let stages: [PBNode] = vm.nodes.filter { n in state.dashboard[n.id]?.kind == .stageA4 }
            if !stages.isEmpty {
                Section(header: Text("Stages on Canvas").font(.headline)) {
                    StagesList(stages: stages).environmentObject(state).environmentObject(vm)
                }
            }
        }
        .padding([.top, .horizontal], 8)
    }
}

// MARK: - Stages List (left pane)
struct StagesList: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    var stages: [PBNode]
    @State private var editingId: String? = nil
    @State private var draft: String = ""
    var body: some View {
        ForEach(stages, id: \.id) { n in
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                if editingId == n.id {
                    TextField("Stage name", text: Binding(
                        get: { draft },
                        set: { draft = $0 }
                    ), onCommit: { commitRename(id: n.id) })
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                } else {
                    Text(stageTitle(for: n)).lineLimit(1)
                        .onTapGesture { vm.selection = n.id; vm.selected = [n.id] }
                        .onTapGesture(count: 2) { beginRename(id: n.id, current: stageTitle(for: n)) }
                }
                Spacer()
                Button { vm.centerOnNode(id: n.id) } label: { Image(systemName: "scope") }.buttonStyle(.plain).help("Center on canvas")
                Menu("⋯") {
                    Button("Bring to Front") { vm.bringToFront(ids: [n.id]) }
                    Button("Send to Back") { vm.sendToBack(ids: [n.id]) }
                    Button("Edit Properties…") { state.pendingEditNodeId = n.id }
                }
            }
            .contentShape(Rectangle())
            .onDrag {
                // Allow repositioning by dragging a Stage row onto canvas
                NSItemProvider(object: NSString(string: "moveStage:\(n.id)"))
            }
        }
        .onMove(perform: move)
    }
    private func stageTitle(for n: PBNode) -> String {
        if let t = state.dashboard[n.id]?.props["title"], !t.isEmpty { return t }
        return n.title ?? n.id
    }
    private func beginRename(id: String, current: String) {
        editingId = id
        draft = current
    }
    private func commitRename(id: String) {
        guard let dash = state.dashboard[id] else { editingId = nil; return }
        var p = dash.props
        p["title"] = draft
        state.updateDashProps(id: id, props: p)
        vm.setNodeTitle(id: id, title: draft)
        editingId = nil
    }
    private func move(from: IndexSet, to: Int) {
        var ordered = stages.map { $0.id }
        ordered.move(fromOffsets: from, toOffset: to)
        vm.reorderStages(orderedStageIds: ordered, isStage: { node in state.dashboard[node.id]?.kind == .stageA4 })
    }
}

// MARK: - OpenAPI Services Library (left panel when in curation mode)
struct OpenAPIServicesLibrary: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    @State private var search: String = ""
    @State private var services: [ServiceDescriptor] = []
    private func reload() {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let root = cwd.appendingPathComponent("Packages/FountainSpecCuration/openapi/v1", isDirectory: true)
        let discovery = ServiceDiscovery(openAPIRoot: root)
        services = (try? discovery.loadServices()) ?? []
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Filter services…", text: $search)
                Spacer()
                Button("Refresh") { reload() }
            }
            List {
                Section(header: Text("OpenAPI Services")) {
                    ForEach(filtered(), id: \.fileName) { svc in
                        HStack {
                            Image(systemName: "square.stack.3d.down.right")
                            VStack(alignment: .leading) { Text(svc.title); Text("\(svc.port)").font(.caption).foregroundColor(.secondary) }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { placeService(svc) }
                        .onDrag {
                            struct ServerPayload: Codable { let serverId: String; let title: String; let port: Int; let spec: String }
                            let id = svc.binaryName ?? svc.title
                            let p = ServerPayload(serverId: id, title: svc.title, port: svc.port, spec: "openapi/v1/\(svc.fileName)")
                            let data = (try? JSONEncoder().encode(p)) ?? Data()
                            return NSItemProvider(item: data as NSData, typeIdentifier: UTType.json.identifier)
                        }
                    }
                }
            }
        }
        .padding([.top, .horizontal], 8)
        .onAppear { reload() }
    }
    private func filtered() -> [ServiceDescriptor] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return services }
        return services.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.fileName.localizedCaseInsensitiveContains(q) }
    }
    private func placeService(_ svc: ServiceDescriptor) {
        // Synthesize a node id and position near origin; use same canonical ports as network builder.
        let g = max(4, vm.grid)
        let x = g * 5, y = g * 5
        let id = normalizeServerId(svc.binaryName ?? svc.title)
        if vm.node(by: id) != nil { vm.selection = id; vm.selected = [id]; return }
        let node = PBNode(id: id, title: svc.title, x: x, y: y, w: 240, h: 120, ports: canonicalSortPorts([
            .init(id: "in", side: .left, dir: .input, type: "data"),
            .init(id: "out", side: .right, dir: .output, type: "data")
        ]))
        vm.nodes.append(node)
        state.registerServerNode(id: id, meta: ServerMeta(serviceId: id, title: svc.title, port: svc.port, specRelativePath: "openapi/v1/\(svc.fileName)"))
        vm.selection = id
        vm.selected = [id]
    }
}

struct TemplateRow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    var template: InstrumentTemplate
    var editMode: Bool
    @State private var draftTitle: String = ""

    private func icon(for kind: String) -> Image {
        switch kind {
        case "mvk.triangle": return Image(systemName: "triangle.fill")
        case "mvk.quad": return Image(systemName: "square.inset.filled")
        case "audiotalk.chat": return Image(systemName: "text.bubble")
        default: return Image(systemName: "circle.grid.3x3")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            icon(for: template.kind.rawValue).frame(width: 20)
            if editMode {
                TextField("Title", text: Binding(get: { draftTitle.isEmpty ? template.title : draftTitle }, set: { draftTitle = $0 }))
                    .onSubmit { state.renameTemplate(id: template.id, to: draftTitle.isEmpty ? template.title : draftTitle); draftTitle = "" }
            } else {
                Text(template.title)
            }
            Spacer()
            if editMode {
                Button { state.toggleHiddenTemplate(id: template.id) } label: { Image(systemName: "eye.slash") }
                    .buttonStyle(.plain).help("Hide")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { createNearOrigin(template: template) }
        .onDrag { dragPayload(for: template) }
    }

    private func dragPayload(for t: InstrumentTemplate) -> NSItemProvider {
        struct Payload: Codable { let templateId: String; let kind: String; let title: String; let w: Int; let h: Int }
        let p = Payload(templateId: t.id, kind: t.kind.rawValue, title: t.title, w: t.defaultWidth, h: t.defaultHeight)
        let data = (try? JSONEncoder().encode(p)) ?? Data()
        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.json.identifier)
    }

    private func base(for kind: String, title: String) -> String {
        if kind == "audiotalk.chat" { return "chat" }
        if kind == "mvk.triangle" { return "tri" }
        if kind == "mvk.quad" { return "quad" }
        if kind == "external.coremidi" { return "midi" }
        let cleaned = title.lowercased().replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty ? "inst" : cleaned
    }

    private func nextId(base: String) -> String {
        var n = 1
        let existing = state.instruments.map { $0.id }
        var candidate = "\(base)_\(n)"
        while existing.contains(candidate) { n += 1; candidate = "\(base)_\(n)" }
        return candidate
    }

    private func createNearOrigin(template t: InstrumentTemplate) {
        guard let c = state.api as? PatchBayClient else { return }
        Task { @MainActor in
            let baseId = base(for: t.kind.rawValue, title: t.title)
            let id = nextId(base: baseId)
            let g = max(4, vm.grid)
            let x = g * 5, y = g * 5
            do {
                if let inst = try await c.createInstrument(id: id, kind: t.kind, title: t.title, x: x, y: y, w: t.defaultWidth, h: t.defaultHeight) {
                    var node = PBNode(id: inst.id, title: inst.title, x: inst.x, y: inst.y, w: inst.w, h: inst.h, ports: [])
                    node.ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
                    node.ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
                    if inst.identity.hasUMPInput == true { node.ports.append(.init(id: "umpIn", side: .left, dir: .input, type: "ump")) }
                    if inst.identity.hasUMPOutput == true { node.ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump")) }
                    vm.nodes.append(node)
                    vm.selection = inst.id
                    vm.selected = [inst.id]
                }
            } catch { }
        }
    }
}

struct DashNodeRow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    var title: String
    var dashKind: DashKind
    var defaultProps: [String:String]
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: dashKind)).frame(width: 20)
            Text(title)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            let g = max(4, vm.grid)
            let x = g * 6, y = g * 6
            let id = create(kind: dashKind, props: defaultProps, x: x, y: y)
            DispatchQueue.main.async { state.pendingEditNodeId = id }
        }
        .onDrag {
            struct DashPayload: Codable { let dashKind: String; let props: [String:String] }
            let p = DashPayload(dashKind: dashKind.rawValue, props: defaultProps)
            let data = (try? JSONEncoder().encode(p)) ?? Data()
            return NSItemProvider(item: data as NSData, typeIdentifier: UTType.json.identifier)
        }
    }
    @discardableResult
    private func create(kind: DashKind, props: [String:String], x: Int, y: Int) -> String {
        let base: String = {
            switch kind {
            case .datasource: return "ds"
            case .query: return "q"
            case .transform: return "xf"
            case .aggregator: return "agg"
            case .topN: return "top"
            case .threshold: return "thr"
            case .panelLine: return "p"
            case .panelStat: return "ps"
            case .panelTable: return "pt"
            case .stageA4: return "stage"
            case .replayPlayer: return "replay"
            case .adapterFountain: return "fxf"
            case .adapterScoreKit: return "fxs"
            }
        }()
        func nextId(base: String) -> String { var n = 1; let ids = Set(vm.nodes.map { $0.id }); var c = "\(base)_\(n)"; while ids.contains(c) { n += 1; c = "\(base)_\(n)" }; return c }
        let id = nextId(base: base)
        var ports: [PBPort] = []
        switch kind {
        case .datasource:
            ports.append(.init(id: "out", side: .right, dir: .output))
        case .panelLine:
            ports.append(.init(id: "in", side: .left, dir: .input))
            ports.append(.init(id: "overlayIn", side: .left, dir: .input))
        case .panelStat, .panelTable:
            ports.append(.init(id: "in", side: .left, dir: .input))
        case .stageA4:
            let page = props["page"]?.lowercased() ?? "a4"
            let height: Double = (page == "letter") ? 792.0 : 842.0
            let baseline = Double(props["baseline"] ?? "12") ?? 12.0
            let mparts = (props["margins"] ?? "18,18,18,18").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let top = mparts.count == 4 ? mparts[0] : 18.0
            let bottom = mparts.count == 4 ? mparts[2] : 18.0
            let usable = max(0.0, height - top - bottom)
            let count = max(1, Int(floor(usable / max(1.0, baseline))))
            for i in 0..<count { ports.append(.init(id: "in\(i)", side: .left, dir: .input)) }
        case .adapterFountain, .adapterScoreKit:
            ports.append(.init(id: "out", side: .right, dir: .output, type: "view"))
        default:
            ports.append(.init(id: "in", side: .left, dir: .input))
            ports.append(.init(id: "out", side: .right, dir: .output))
        }
        let stageSize: (Int, Int) = {
            let z = max(0.0001, vm.zoom)
            let baseW = 480, baseH = 680
            let w = Int(CGFloat(baseW) / z)
            let h = Int(CGFloat(baseH) / z)
            return (w, h)
        }()
        let node = PBNode(id: id, title: titleFrom(kind), x: x, y: y,
                          w: (kind == .stageA4 ? stageSize.0 : 260),
                          h: (kind == .stageA4 ? stageSize.1 : (kind == .panelLine ? 200 : (kind == .panelStat ? 140 : (kind == .panelTable ? 200 : (kind == .replayPlayer ? 180 : 140))))),
                          ports: canonicalSortPorts(ports))
        vm.nodes.append(node)
        var propsToSave2 = props
        if kind == .stageA4 {
            func parseStageIndex(_ title: String?) -> Int? {
                guard let s = title else { return nil }
                let t = s.trimmingCharacters(in: .whitespaces)
                guard t.lowercased().hasPrefix("stage ") else { return nil }
                return Int(t.dropFirst("stage ".count))
            }
            var maxIdx = 0
            for (_, node) in state.dashboard where node.kind == .stageA4 { if let n = parseStageIndex(node.props["title"]) { maxIdx = max(maxIdx, n) } }
            for n in vm.nodes where state.dashboard[n.id]?.kind == .stageA4 { if let i = parseStageIndex(n.title) { maxIdx = max(maxIdx, i) } }
            let defaultTitle = "Stage \(maxIdx + 1)"
            let current = propsToSave2["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if current == nil || current == "" || current == "The Stage" { propsToSave2["title"] = defaultTitle }
            vm.setNodeTitle(id: id, title: propsToSave2["title"] ?? defaultTitle)
        }
        state.registerDashNode(id: id, kind: kind, props: propsToSave2)
        vm.selection = id; vm.selected = [id]
        // Auto-wire common patterns for double-click creations
        func lastId(where pred: (String, DashKind) -> Bool) -> String? {
            let ids = vm.nodes.map { $0.id }
            for nid in ids.reversed() { if let k = state.dashboard[nid]?.kind, pred(nid, k) { return nid } }
            return nil
        }
        switch kind {
        case .query:
            if let ds = lastId(where: { _, k in k == .datasource }) { _ = vm.ensureEdge(from: (ds,"out"), to: (id,"in")) }
        case .transform, .aggregator, .topN, .threshold:
            if let upstream = vm.selection ?? lastId(where: { _, k in k == .query || k == .transform }) { _ = vm.ensureEdge(from: (upstream,"out"), to: (id,"in")) }
        case .panelLine:
            if let up = vm.selection ?? lastId(where: { _, k in k == .aggregator || k == .transform || k == .query }) { _ = vm.ensureEdge(from: (up,"out"), to: (id,"in")) }
        case .panelStat:
            if let agg = lastId(where: { _, k in k == .aggregator }) { _ = vm.ensureEdge(from: (agg,"out"), to: (id,"in")) }
        case .panelTable:
            if let top = lastId(where: { _, k in k == .topN }) { _ = vm.ensureEdge(from: (top,"out"), to: (id,"in")) }
        case .stageA4:
            if let up = lastId(where: { _, k in k == .panelLine || k == .panelStat || k == .panelTable || k == .adapterFountain || k == .adapterScoreKit }) { _ = vm.ensureEdge(from: (up,"out"), to: (id,"in")) }
        case .replayPlayer:
            break
        case .adapterFountain, .adapterScoreKit:
            if let stage = lastId(where: { _, k in k == .stageA4 }) { _ = vm.ensureEdge(from: (id,"out"), to: (stage,"in")) }
        case .datasource:
            break
        }
        return id
    }
    private func titleFrom(_ k: DashKind) -> String { switch k { case .datasource: return "prom.datasource"; case .query: return "prom.query"; case .transform: return "prom.transform"; case .aggregator: return "prom.aggregator"; case .topN: return "prom.topN"; case .threshold: return "prom.threshold"; case .panelLine: return "prom.panel.line"; case .panelStat: return "prom.panel.stat"; case .panelTable: return "prom.panel.table"; case .stageA4: return "renderer.stage.a4"; case .replayPlayer: return "replay.player"; case .adapterFountain: return "adapter.fountain→teatro"; case .adapterScoreKit: return "adapter.scorekit→teatro" } }
    private func iconName(for k: DashKind) -> String { switch k { case .datasource: return "bolt.horizontal"; case .query: return "text.magnifyingglass"; case .transform: return "arrow.triangle.2.circlepath"; case .aggregator: return "sum"; case .topN: return "list.number"; case .threshold: return "line.diagonal.arrow"; case .panelLine: return "chart.line.uptrend.xyaxis"; case .panelStat: return "gauge"; case .panelTable: return "tablecells"; case .stageA4: return "doc.richtext"; case .replayPlayer: return "play.rectangle"; case .adapterFountain: return "text.document"; case .adapterScoreKit: return "music.quarternote.3" } }
}

enum FlowNodeKind: String, Codable { case audioInput, analyzer, noteProcessor, transportEndpoint }

struct FlowNodeRow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    var title: String
    var flowKind: FlowNodeKind
    var body: some View {
        HStack { Image(systemName: iconName()); Text(title); Spacer() }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { createNearOrigin() }
            .onDrag { dragPayload() }
    }
    private func iconName() -> String {
        switch flowKind { case .audioInput: return "waveform"; case .analyzer: return "chart.bar"; case .noteProcessor: return "pianokeys"; case .transportEndpoint: return "dot.radiowaves.left.and.right" }
    }
    private func dragPayload() -> NSItemProvider {
        struct Payload: Codable { let flowKind: String }
        let data = try? JSONEncoder().encode(Payload(flowKind: flowKind.rawValue))
        return NSItemProvider(item: (data ?? Data()) as NSData, typeIdentifier: UTType.json.identifier)
    }
    private func createNearOrigin() {
        let g = max(4, vm.grid)
        let x = g * 5, y = g * 5
        let base: String = {
            switch flowKind { case .audioInput: return "audioIn"; case .analyzer: return "analyzer"; case .noteProcessor: return "noteProc"; case .transportEndpoint: return "endpoint" }
        }()
        var id = base
        var n = 1
        while vm.node(by: id) != nil { n += 1; id = base + "_\(n)" }
        var ports: [PBPort] = []
        switch flowKind {
        case .audioInput:
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
        case .analyzer:
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
            ports.append(.init(id: "out", side: .right, dir: .output, type: "data"))
        case .noteProcessor:
            ports.append(.init(id: "in", side: .left, dir: .input, type: "data"))
            ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump"))
        case .transportEndpoint:
            ports.append(.init(id: "ciIn", side: .left, dir: .input, type: "ci"))
            ports.append(.init(id: "ciOut", side: .right, dir: .output, type: "ci"))
            ports.append(.init(id: "umpIn", side: .left, dir: .input, type: "ump"))
            ports.append(.init(id: "umpOut", side: .right, dir: .output, type: "ump"))
        }
        let node = PBNode(id: id, title: title, x: x, y: y, w: flowKind == .transportEndpoint ? 260 : 220, h: 120, ports: canonicalSortPorts(ports))
        vm.nodes.append(node)
        vm.selection = id
        vm.selected = [id]
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
/* struct InspectorPane: View {
    enum Tab: String, CaseIterable { case chat = "Chat", corpus = "Stellwerk" }
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vm: EditorVM
    @State private var tab: Tab = .chat
    @State private var tabsOrder: [Tab] = Tab.allCases
    @State private var storeId: String = "openapi-curation"
    @State private var previewLink: Components.Schemas.CreateLink? = nil
    @State private var showPreview: Bool = false
    @State private var showApplyAllConfirm: Bool = false
    @State private var diffSummary: String = ""
    enum StellwerkSection: String, CaseIterable { case summary = "Summary", disconnected = "Disconnected", diff = "Diff vs Store", coverage = "CI/PE Coverage", mappings = "Mappings", health = "Health", store = "Store" }
    @State private var stellwerkSections: [StellwerkSection] = StellwerkSection.allCases
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(tabsOrder, id: \.self) { t in
                    Text(t.rawValue)
                        .font(.callout)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(tab == t ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(tab == t ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.6), lineWidth: tab == t ? 1.5 : 1)
                        )
                        .onTapGesture { tab = t }
                        .onDrag { NSItemProvider(object: NSString(string: t.rawValue)) }
                        .onDrop(of: [UTType.text], isTargeted: .constant(false)) { providers in
                            guard let provider = providers.first else { return false }
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
                                guard let data = data, let name = String(data: data, encoding: .utf8), let fromTab = Tab(rawValue: name) else { return }
                                DispatchQueue.main.async {
                                    if let fromIndex = tabsOrder.firstIndex(of: fromTab), let toIndex = tabsOrder.firstIndex(of: t), fromIndex != toIndex {
                                        var arr = tabsOrder
                                        let item = arr.remove(at: fromIndex)
                                        arr.insert(item, at: toIndex)
                                        tabsOrder = arr
                                        saveTabsOrder()
                                    }
                                }
                            }
                            return true
                        }
                }
                Spacer()
            }
            switch tab {
            case .corpus:
                corpusView
            case .chat:
                AssistantPane(seedQuestion: "What's in the corpus?", autoSendOnAppear: true)
            }
        }
        .task { await state.refreshLinks(); loadTabsOrder() }
        .onChange(of: tabsOrder) { _, _ in saveTabsOrder() }
    }
    private func computeDisconnected(vm: EditorVM) -> [String] {
        var deg: [String: Int] = Dictionary(uniqueKeysWithValues: vm.nodes.map { ($0.id, 0) })
        for e in vm.edges {
            let f = String(e.from.split(separator: ".").first ?? "")
            let t = String(e.to.split(separator: ".").first ?? "")
            if deg[f] != nil { deg[f]! += 1 }
            if deg[t] != nil { deg[t]! += 1 }
        }
        return deg.filter { $0.value == 0 }.map { $0.key }
    }
    private func selectDisconnected(vm: EditorVM) {
        let ids = computeDisconnected(vm: vm)
        vm.selected = Set(ids)
        vm.selection = ids.first
    }
    private func computeCoverage() -> String {
        let total = state.instruments.count
        let peReady = state.instruments.filter { !$0.propertySchema.properties.isEmpty }.count
        return "CI/PE: \(peReady)/\(total) instruments expose properties; subscriptions shown per service links."
    }
    private func mappingLines() -> [String] {
        state.links.compactMap { l in
            switch l.kind {
            case .property:
                if let p = l.property, let f = p.from, let t = p.to { return "prop: \(f) -> \(t)" }
                return nil
            case .ump:
                if let u = l.ump {
                    var parts: [String] = []
                    parts.append("ump: endpoint=\(u.source.endpointId) g=\(u.source.group) ch=\(u.source.channel)")
                    if let cc = u.source.cc { parts.append("cc=\(cc)") }
                    if let note = u.source.note { parts.append("note=\(note)") }
                    var mapStr = ""
                    if let m = u.map { mapStr = " scale=\(m.scale ?? 1.0) offset=\(m.offset ?? 0.0)" }
                    let to = u.to
                    return parts.joined(separator: " ") + " -> \(to)" + mapStr
                }
                return nil
            }
        }
    }
    private func computeHealth(vm: EditorVM) -> String {
        let total = vm.nodes.count
        let bad = vm.nodes.filter { canonicalSortPorts($0.ports) != $0.ports }.count
        let dangling = computeDisconnected(vm: vm).count
        return "portsOK=\(total-bad)/\(total), disconnected=\(dangling)"
    }
    private func saveCurrent(storeId: String, vm: EditorVM) async {
        if let c = state.api as? PatchBayClient {
            let doc = vm.toGraphDoc(with: state.instruments)
            _ = try? await c.putStoredGraph(id: storeId, doc: doc)
            await state.refreshStore()
        }
    }
    private func loadStored(id: String, vm: EditorVM) async {
        if let c = state.api as? PatchBayClient, let sg = try? await c.getStoredGraph(id: id) {
            vm.applyGraphDoc(sg.doc)
        }
    }
    private func computeDiff(storeId: String, vm: EditorVM) async -> String {
        guard let c = state.api as? PatchBayClient, let sg = try? await c.getStoredGraph(id: storeId) else { return "No stored graph \(storeId)" }
        let currIds = Set(state.instruments.map { $0.id })
        let storeIds = Set(sg.doc.instruments.map { $0.id })
        let addedI = currIds.subtracting(storeIds)
        let removedI = storeIds.subtracting(currIds)
        let currEdges = Set(state.links.map { ($0.kind.rawValue, $0.property?.from ?? "", $0.property?.to ?? "", $0.ump?.to ?? "") }.map { "\($0)|\($1)|\($2)|\($3)" })
        let storeEdges = Set(sg.doc.links.map { l in (l.kind.rawValue, l.property?.from ?? "", l.property?.to ?? "", l.ump?.to ?? "") }.map { "\($0)|\($1)|\($2)|\($3)" })
        let addedL = currEdges.subtracting(storeEdges)
        let removedL = storeEdges.subtracting(currEdges)
        return "+I \(addedI.count) −I \(removedI.count); +L \(addedL.count) −L \(removedL.count)"
    }
    private func loadTabsOrder() {
        let key = "pb.tabsOrder.v1"
        if let raw = UserDefaults.standard.array(forKey: key) as? [String] {
            let mapped = raw.compactMap(Tab.init(rawValue:))
            if !mapped.isEmpty { tabsOrder = mapped }
        }
    }
    private func saveTabsOrder() {
        let key = "pb.tabsOrder.v1"
        UserDefaults.standard.set(tabsOrder.map { $0.rawValue }, forKey: key)
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
    /* @ViewBuilder var instrumentsView: some View {
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
                HStack {
                    Button("Discover CI (Mock)") {
                        // Place a function block near center and connect a CI link from the selected instrument's 'out' port
                        let id = "funcBlock_\(Int(Date().timeIntervalSince1970))"
                        let g = max(4, vm.grid)
                        let x = (inst.x + inst.w) + g * 10
                        let y = inst.y
                        var ports: [PBPort] = []
                        ports.append(.init(id: "ciIn", side: .left, dir: .input, type: "ci"))
                        ports.append(.init(id: "ciOut", side: .right, dir: .output, type: "ci"))
                        ports.append(.init(id: "peIn", side: .left, dir: .input, type: "pe"))
                        ports.append(.init(id: "peOut", side: .right, dir: .output, type: "pe"))
                        let node = PBNode(id: id, title: "Function Block", x: x, y: y, w: 240, h: 140, ports: canonicalSortPorts(ports))
                        vm.nodes.append(node)
                        // Wire inst.out -> funcBlock.ciIn
                        _ = vm.ensureEdge(from: (inst.id, "out"), to: (id, "ciIn"))
                        vm.selection = id
                        vm.selected = [id]
                    }
                    Spacer()
                }
                Divider().padding(.vertical, 4)
                HStack {
                    Text("Corpus Overview").font(.headline)
                    Spacer()
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(state.corpusOverviewLine(), forType: .string) }
                }
                Text(state.corpusOverviewLine()).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                Text("No instrument selected").foregroundColor(.secondary)
            }
        }
    }
    */
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
        ScrollView { VStack(alignment: .leading, spacing: 8) {
            ForEach(stellwerkSections, id: \.self) { sec in
                sectionHeader(sec)
                    .onDrag { NSItemProvider(object: NSString(string: sec.rawValue)) }
                    .onDrop(of: [UTType.text], isTargeted: .constant(false)) { providers in
                        guard let provider = providers.first else { return false }
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
                            guard let data = data, let name = String(data: data, encoding: .utf8), let from = StellwerkSection(rawValue: name) else { return }
                            DispatchQueue.main.async {
                                if let fromIndex = stellwerkSections.firstIndex(of: from), let toIndex = stellwerkSections.firstIndex(of: sec), fromIndex != toIndex {
                                    var arr = stellwerkSections
                                    let item = arr.remove(at: fromIndex)
                                    arr.insert(item, at: toIndex)
                                    stellwerkSections = arr
                                    saveStellwerkOrder()
                                }
                            }
                        }
                        return true
                    }
                sectionBody(sec)
                Divider().padding(.vertical, 4)
            }
        } }
        .onAppear { loadStellwerkOrder() }
    }
    private func sectionHeader(_ sec: StellwerkSection) -> some View {
        HStack { Text(sec.rawValue).font(.headline); Spacer()
            switch sec {
            case .summary:
                Button("Refresh") { Task { await state.refresh(); await state.refreshLinks(); await state.makeSnapshot() } }
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(state.corpusOverviewLine(), forType: .string) }
                Button("Send to Chat") { Task { await state.ask(question: "Describe current corpus.\n\n" + state.corpusOverviewLine(), vm: vm) } }
            case .disconnected:
                Button("Select") { selectDisconnected(vm: vm) }
            case .diff:
                TextField("Graph ID", text: $storeId).frame(width: 160)
                Button("Compute") { Task { diffSummary = await computeDiff(storeId: storeId, vm: vm) } }
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(diffSummary, forType: .string) }
            case .coverage:
                EmptyView()
            case .mappings:
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(mappingLines().joined(separator: "\n"), forType: .string) }
            case .health:
                EmptyView()
            case .store:
                Button("Refresh List") { Task { await state.refreshStore() } }
            }
        }
    }
    @ViewBuilder private func sectionBody(_ sec: StellwerkSection) -> some View {
        switch sec {
        case .summary:
            Text(state.corpusOverviewLine()).font(.system(.body, design: .monospaced))
        case .disconnected:
            let disconnected = computeDisconnected(vm: vm)
            if disconnected.isEmpty { Text("All nodes connected").foregroundColor(.secondary) }
            else { Text(disconnected.joined(separator: ", ")).font(.system(.caption, design: .monospaced)) }
        case .diff:
            if !diffSummary.isEmpty { Text(diffSummary).font(.system(.caption, design: .monospaced)) }
        case .coverage:
            Text(computeCoverage()).font(.system(.caption, design: .monospaced))
        case .mappings:
            ScrollView { VStack(alignment: .leading, spacing: 2) { ForEach(mappingLines(), id: \.self) { Text($0).font(.system(.caption, design: .monospaced)) } } }.frame(maxHeight: 120)
        case .health:
            Text(computeHealth(vm: vm)).font(.system(.caption, design: .monospaced))
        case .store:
            VStack(alignment: .leading, spacing: 6) {
                Text("Store (Save/Load)").font(.subheadline)
                HStack {
                    TextField("Graph ID", text: $storeId).frame(width: 160)
                    Button("Save Current") { Task { await saveCurrent(storeId: storeId, vm: vm) } }
                    Spacer()
                }
                if state.stored.isEmpty { Text("No stored graphs").foregroundColor(.secondary) }
                ScrollView { ForEach(state.stored, id: \.id) { item in HStack { Text(item.id).font(.system(.body, design: .monospaced)); Spacer(); Button("Load") { Task { await loadStored(id: item.id, vm: vm) } } } } }
            }
        }
    }
    private func loadStellwerkOrder() {
        let key = "pb.stellwerkOrder.v1"
        if let raw = UserDefaults.standard.array(forKey: key) as? [String] {
            let mapped = raw.compactMap(StellwerkSection.init(rawValue:))
            if !mapped.isEmpty { stellwerkSections = mapped }
        }
    }
    private func saveStellwerkOrder() {
        let key = "pb.stellwerkOrder.v1"
        UserDefaults.standard.set(stellwerkSections.map { $0.rawValue }, forKey: key)
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
    var seedQuestion: String? = nil
    var autoSendOnAppear: Bool = false
    @State private var chatInput: String = "What instruments and links are present?"
    @FocusState private var chatFocused: Bool
    @State private var expanded: Bool = false
    @State private var showModelSheet: Bool = false
    @State private var customModel: String = ""
    @State private var showGatewaySheet: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assistant").font(.headline)
                Spacer()
                Button(action: { state.useLLM.toggle(); state.saveUseLLM() }) {
                    HStack(spacing: 6) {
                        let color: Color = {
                            if !state.useLLM { return .gray }
                            switch state.gatewayStatus { case .ok: return .green; case .checking: return .yellow; case .bad: return .red; case .unknown: return .gray }
                        }()
                        Circle().fill(color).frame(width: 8, height: 8)
                        let label: String = {
                            if !state.useLLM { return "LLM: Off" }
                            switch state.gatewayStatus { case .ok: return "LLM: On"; case .checking: return "LLM: Checking"; case .bad(let e): return "LLM: Error (\(e))"; case .unknown: return "LLM: Unknown" }
                        }()
                        Text(label).font(.caption)
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Toggle LLM usage (persists)")
                Menu("Model: \(state.llmModel)") {
                    ForEach(["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "o4-mini"], id: \.self) { name in
                        Button(action: { state.llmModel = name; state.saveLLMModel() }) {
                            if state.llmModel == name { Image(systemName: "checkmark") }
                            Text(name)
                        }
                    }
                    Divider()
                    Button("Custom…") { showModelSheet = true }
                }
                .menuStyle(.borderlessButton)
                .help("Choose Gateway model (persists)")
                Menu("Gateway") {
                    Button("Test Connectivity") { Task { await state.checkGateway() } }
                    Button("Set URL…") { showGatewaySheet = true }
                    Text("Current: \(state.gatewayURL.absoluteString)").font(.caption)
                }
            }
            .sheet(isPresented: $showModelSheet) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set Custom Model").font(.headline)
                    TextField("model id", text: $customModel)
                        .frame(width: 260)
                    HStack { Spacer(); Button("Cancel") { showModelSheet = false }; Button("Save") { state.llmModel = customModel.trimmingCharacters(in: .whitespacesAndNewlines); state.saveLLMModel(); showModelSheet = false } }
                }
                .padding(14)
                .frame(width: 320)
            }
            .sheet(isPresented: $showGatewaySheet) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set Gateway URL").font(.headline)
                    TextField("http://127.0.0.1:8010", text: Binding(get: { state.gatewayURL.absoluteString }, set: { if let u = URL(string: $0) { state.gatewayURL = u } }))
                        .frame(width: 360)
                    HStack { Spacer(); Button("Cancel") { showGatewaySheet = false }; Button("Save") { state.saveGatewayURL(); Task { await state.checkGateway() }; showGatewaySheet = false } }
                }
                .padding(14)
                .frame(width: 400)
            }
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
                    Button("Describe Selection") { Task {
                        if let sel = vm.selection, let node = vm.node(by: sel) {
                            // Use the same path as `ask` would, but synthesize a question so history captures it.
                            let q = "Describe \(node.title ?? node.id)"
                            await state.ask(question: q, vm: vm)
                        } else {
                            NSPasteboard.general.clearContents();
                            NSPasteboard.general.setString("Select a node to describe.", forType: .string)
                        }
                    } }
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
            // Field‑Guide tool result (artifact + ETag) — Preview/Apply controls
            if let etag = state.latestArtifactETag, let path = state.latestArtifactPath {
                Divider().padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Guide Result").font(.headline)
                    Text("ETag: \(etag)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    Text(path.lastPathComponent).font(.system(.caption, design: .monospaced))
                    HStack(spacing: 8) {
                        Button("Preview Artifact") { state.openLatestArtifact() }
                        Button("Apply to Canvas") { Task { let msg = await state.applyLatestArtifactToCanvas(vm: vm); state.chat.append(.init(role: "assistant", text: msg)) } }
                        Button("Refresh Artifacts") { state.refreshArtifacts() }
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
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
        .onAppear {
            if state.chat.isEmpty, let s = seedQuestion {
                chatInput = s + "\n\n" + state.corpusOverviewLine()
                if autoSendOnAppear { Task { await state.ask(question: chatInput, vm: vm) } }
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
        // Ports: deterministic order (left: in, umpIn; right: out, umpOut)
        vm.addPort(to: id, side: .left, dir: .input, id: "in", type: "data")
        if inst.identity.hasUMPInput == true { vm.addPort(to: id, side: .left, dir: .input, id: "umpIn", type: "ump") }
        vm.addPort(to: id, side: .right, dir: .output, id: "out", type: "data")
        if inst.identity.hasUMPOutput == true { vm.addPort(to: id, side: .right, dir: .output, id: "umpOut", type: "ump") }
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
*/

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
    }
}

// MARK: - Renderer Preview Window
struct RendererPreviewView: View {
    @EnvironmentObject var state: AppState
    let id: String
    let dash: DashNode
    @ObservedObject var vm: EditorVM
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dash.props["title"] ?? (dash.kind.rawValue)).font(.headline)
            content()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
        }
        .padding(12)
    }
    @ViewBuilder
    private func content() -> some View {
        switch dash.kind {
        case .panelLine:
            if let up = upstream(for: id, port: "in"), case .timeSeries(let s) = state.dashOutputs[up] ?? .none {
                LineOverlayPanelView(title: dash.props["title"] ?? dash.kind.rawValue, series: s, annotations: [])
            } else { noData }
        case .panelStat:
            if let up = upstream(for: id, port: "in"), let p = state.dashOutputs[up] {
                switch p {
                case .scalar(let v): StatPanelView(title: dash.props["title"] ?? dash.kind.rawValue, value: v)
                case .timeSeries(let s): StatPanelView(title: dash.props["title"] ?? dash.kind.rawValue, value: s.first?.points.last?.1 ?? 0)
                default: noData
                }
            } else { noData }
        case .panelTable:
            if let up = upstream(for: id, port: "in"), case .table(let rows) = state.dashOutputs[up] ?? .none {
                TablePanelView(title: dash.props["title"] ?? dash.kind.rawValue, rows: rows)
            } else { noData }
        default:
            VStack(alignment: .leading) { Text("Not a renderer node").foregroundStyle(.secondary) }
        }
    }
    private var noData: some View {
        VStack(alignment: .leading) { Text("No data").font(.caption).foregroundStyle(.secondary) }
    }
    private func upstream(for nodeId: String, port: String) -> String? {
        vm.edges.first(where: { $0.to == nodeId+"."+port })?.from.split(separator: ".").first.map(String.init)
    }
}
