import SwiftUI
import FountainStoreClient
import LauncherSignature

@main
struct EngravingMacApp: App {
    @StateObject private var model = AppModel()

    init() {
        verifyLauncherSignature()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task { await model.load() }
        }
        .windowStyle(.titleBar)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var corpusId: String
    @Published var corpora: [String] = []
    @Published var pages: [PageDoc] = []
    @Published var selected: PageDoc?
    @Published var selectedCode: String = ""
    @Published var status: String = ""
    @Published var findings: [Finding] = []
    @Published var showArc: Bool = false
    @Published var arcPhases: [ArcPhase] = []
    @Published var arcTotal: Int = 0

    private let store: FountainStoreClient

    init() {
        let env = ProcessInfo.processInfo.environment
        self.corpusId = env["ENGRAVING_CORPUS_ID"] ?? "engraving-lab"
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                self.store = FountainStoreClient(client: disk)
            } else { self.store = FountainStoreClient(client: EmbeddedFountainStoreClient()) }
        } else {
            self.store = FountainStoreClient(client: EmbeddedFountainStoreClient())
        }
    }

    func load() async {
        do {
            await loadCorpora()
            let (total, list) = try await fetchPages()
            pages = list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            status = "Loaded \(total) pages from \(corpusId)"
            if selected == nil { selected = pages.first }
            await loadCode()
            await loadFindings()
        } catch { status = "Load error: \(error.localizedDescription)" }
    }

    func reload() async { await load() }

    func fetchPages(limit: Int = 500, offset: Int = 0) async throws -> (Int, [PageDoc]) {
        let resp = try await store.query(corpusId: corpusId, collection: "pages", query: Query(filters: ["corpusId": corpusId], limit: limit, offset: offset))
        let list = try resp.documents.map { try JSONDecoder().decode(PageDoc.self, from: $0) }
        return (list.count, list)
    }

    func loadCorpora() async {
        do {
            let (_, list) = try await store.listCorpora(limit: 9999, offset: 0)
            self.corpora = list
            if !list.contains(corpusId), let first = list.first { self.corpusId = first }
        } catch {
            self.corpora = [corpusId]
        }
    }

    func loadCode() async {
        guard let sel = selected else { selectedCode = ""; return }
        // Our ingest names code segment as "<pageId>:code"
        let segIdPrefix = sel.pageId + ":"
        do {
            let resp = try await store.query(corpusId: corpusId, collection: "segments", query: Query(filters: ["corpusId": corpusId, "pageId": sel.pageId], limit: 50, offset: 0))
            struct SegmentDoc: Codable { let segmentId: String; let pageId: String; let kind: String; let text: String }
            let list = try resp.documents.map { try JSONDecoder().decode(SegmentDoc.self, from: $0) }
            if let code = list.first(where: { $0.kind == "code" || $0.segmentId.hasPrefix(segIdPrefix) })?.text {
                selectedCode = code
            } else {
                selectedCode = "(no code segment found)"
            }
        } catch { selectedCode = "(error loading segments: \(error.localizedDescription))" }
    }

    // MARK: - Quick actions
    func bootstrap() async {
        do {
            _ = try await store.createCorpus(CorpusCreateRequest(corpusId: corpusId))
            let planId = "plan:starter"
            let page = PageDoc(corpusId: corpusId, pageId: planId, url: "store://plan/starter", host: "store", title: "Engraving Plan")
            try await store.addPage(.init(corpusId: page.corpusId, pageId: page.pageId, url: page.url, host: page.host, title: page.title))
            let notes = """
            - [ ] Set up corpus
            - [ ] Ingest code
            - [ ] Run rules
            - [ ] Baseline and drift
            """
            try await store.addSegment(.init(corpusId: corpusId, segmentId: "\(planId):notes", pageId: planId, kind: "notes", text: notes))
            status = "Bootstrapped corpus \(corpusId) with starter plan"
            await load()
        } catch { status = "Bootstrap error: \(error.localizedDescription)" }
    }

    func ingestCode(root: URL? = nil, limit: Int = 200) async {
        let repoRoot: URL = root ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["FOUNTAINAI_ROOT"] ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: repoRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            status = "Cannot enumerate \(repoRoot.path)"; return
        }
        var count = 0
        while let item = enumerator.nextObject() as? URL {
            let url = item
            if count >= limit { break }
            if url.pathExtension != "swift" { continue }
            let rel = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            let pageId = "file:\(rel)"
            do {
                try await store.addPage(.init(corpusId: corpusId, pageId: pageId, url: url.absoluteString, host: "repo", title: rel))
                let code = (try? String(contentsOf: url)) ?? ""
                try await store.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):code", pageId: pageId, kind: "code", text: code))
                count += 1
            } catch {
                // continue on error
            }
        }
        status = "Ingested \(count) files from \(repoRoot.lastPathComponent)"
        await load()
    }

    // MARK: - Baseline / Drift / Arc / Findings
    func createBaseline(label: String? = nil) async {
        let ts = ISO8601DateFormatter().string(from: Date())
        let id = "baseline-\(label ?? "auto")-\(ts)"
        var pagesSnapshot: [String] = []
        if let (_, list) = try? await fetchPages() { pagesSnapshot = list.map { $0.pageId } }
        let content: [String: Any] = ["kind": "engraving-baseline", "time": ts, "pages": pagesSnapshot]
        do {
            let json = String(data: try JSONSerialization.data(withJSONObject: content), encoding: .utf8) ?? "{}"
            _ = try await store.addBaseline(.init(corpusId: corpusId, baselineId: id, content: json))
            status = "Baseline created: \(id)"
        } catch { status = "Baseline error: \(error.localizedDescription)" }
    }

    func computeDrift() async {
        do {
            let (_, baselines) = try await store.listBaselines(corpusId: corpusId)
            let prev = baselines.last?.baselineId ?? "(none)"
            let (_, pagesNow) = try await fetchPages()
            let driftObj: [String: Any] = [
                "kind": "engraving-drift",
                "from": prev,
                "pages": pagesNow.count,
                "time": ISO8601DateFormatter().string(from: Date())
            ]
            let json = String(data: try JSONSerialization.data(withJSONObject: driftObj), encoding: .utf8) ?? "{}"
            let id = "drift-\(Int(Date().timeIntervalSince1970))"
            _ = try await store.addDrift(.init(corpusId: corpusId, driftId: id, content: json))
            status = "Drift recorded vs \(prev)"
        } catch { status = "Drift error: \(error.localizedDescription)" }
    }

    func fetchArc() async {
        do {
            let aware = URL(string: ProcessInfo.processInfo.environment["AWARENESS_URL"] ?? "http://127.0.0.1:8001")!
            var comps = URLComponents(url: aware.appendingPathComponent("/corpus/semantic-arc"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "corpus_id", value: corpusId)]
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let total = obj["total"] as? Int ?? 0
            let arc = (obj["arc"] as? [[String: Any]] ?? []).map { d in
                ArcPhase(phase: d["phase"] as? String ?? "", weight: d["weight"] as? Int ?? 0, pct: d["pct"] as? Double ?? 0)
            }
            self.arcPhases = arc
            self.arcTotal = total
            self.showArc = true
        } catch { self.status = "Arc fetch error: \(error.localizedDescription)" }
    }

    func loadFindings() async {
        // Load latest patterns summaries for the corpus
        do {
            let resp = try await store.query(corpusId: corpusId, collection: "patterns", query: Query(filters: ["corpusId": corpusId], limit: 200, offset: 0))
            struct PatternsDoc: Codable { let patternsId: String; let content: String }
            let list = try resp.documents.map { try JSONDecoder().decode(PatternsDoc.self, from: $0) }
            var out: [Finding] = []
            for p in list {
                if let data = p.content.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let findings = obj["findings"] as? [[String: Any]] {
                        for f in findings { out.append(Finding(title: (f["title"] as? String) ?? p.patternsId, severity: (f["severity"] as? String) ?? "info", location: f["file"] as? String, line: f["line"] as? Int)) }
                    } else {
                        out.append(Finding(title: p.patternsId, severity: "summary", location: nil, line: nil))
                    }
                }
            }
            self.findings = out
        } catch { self.findings = [] }
    }

    func runRules() async {
        // Simple inline rules: flag TODO:, fatalError(, long lines > 120
        do {
            let resp = try await store.query(corpusId: corpusId, collection: "segments", query: Query(filters: ["corpusId": corpusId, "kind": "code"], limit: 2000, offset: 0))
            struct SegmentDoc: Codable { let segmentId: String; let pageId: String; let kind: String; let text: String }
            let segs = try resp.documents.map { try JSONDecoder().decode(SegmentDoc.self, from: $0) }
            var arr: [[String: Any]] = []
            for s in segs {
                let file = s.pageId.replacingOccurrences(of: "file:", with: "")
                let lines = s.text.split(separator: "\n", omittingEmptySubsequences: false)
                for (idx, line) in lines.enumerated() {
                    let t = String(line)
                    if t.contains("TODO:") { arr.append(["title": "TODO present", "severity": "info", "file": file, "line": idx+1]) }
                    if t.contains("fatalError(") { arr.append(["title": "fatalError used", "severity": "error", "file": file, "line": idx+1]) }
                    if t.count > 120 { arr.append(["title": "Long line (>120)", "severity": "warn", "file": file, "line": idx+1]) }
                }
            }
            let payload: [String: Any] = ["kind": "rules-findings", "findings": arr]
            let json = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? "{}"
            let pid = "rules-\(Int(Date().timeIntervalSince1970))"
            _ = try await store.addPatterns(.init(corpusId: corpusId, patternsId: pid, content: json))
            status = "Rules completed: \(arr.count) findings"
            await loadFindings()
        } catch { status = "Rules error: \(error.localizedDescription)" }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationSplitView {
            // LEFT: Sidebar (pages)
            List(selection: $model.selected) {
                ForEach(model.pages) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.headline)
                        Text(p.pageId).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(p)
                }
            }
            .navigationTitle("Pages")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } content: {
            // CENTER: Code viewer
            Group {
                if model.pages.isEmpty {
                    QuickStartView().environmentObject(model)
                } else if let p = model.selected {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(p.title).font(.title2)
                        Text(p.url).font(.caption).foregroundStyle(.secondary)
                        Divider()
                        ScrollView {
                            Text(model.selectedCode)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        Spacer()
                        Text(model.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    VStack { Text("No selection") }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 700)
        } detail: {
            // RIGHT: Inspector (findings)
            InspectorView(findings: model.findings)
                .frame(minWidth: 260)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("Corpus", selection: $model.corpusId) {
                    ForEach(model.corpora, id: \.self) { Text($0).tag($0) }
                }
                Button("Reload") { Task { await model.reload() } }
                Button("Baseline") { Task { await model.createBaseline() } }
                Button("Diff") { Task { await model.computeDrift() } }
                Button("Arc") { Task { await model.fetchArc() } }
                Button("Rules") { Task { await model.runRules() } }
            }
        }
        .onChange(of: model.corpusId) { _ in Task { await model.load() } }
        .sheet(isPresented: $model.showArc) {
            ArcSheet(phases: model.arcPhases, total: model.arcTotal, corpus: model.corpusId)
                .frame(minWidth: 560, minHeight: 360)
        }
    }
}

struct PageDoc: Codable, Identifiable, Hashable {
    var id: String { pageId }
    let corpusId: String
    let pageId: String
    let url: String
    let host: String
    let title: String
}

struct QuickStartView: View {
    @EnvironmentObject var model: AppModel
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Engraving").font(.largeTitle).bold()
            Text("Corpus: \(model.corpusId)").foregroundStyle(.secondary)
            Divider()
            Text("Get started:").font(.headline)
            HStack(spacing: 12) {
                Button("Bootstrap Corpus") { Task { busy = true; await model.bootstrap(); busy = false } }
                Button("Ingest Code (repo root)") {
                    Task { busy = true; await model.ingestCode(); busy = false }
                }
            }
            Text(model.status).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .overlay(alignment: .bottomTrailing) {
            if busy { ProgressView().padding() }
        }
    }
}

struct FindingsView: View {
    var findings: [Finding]
    var body: some View {
        if findings.isEmpty {
            Text("No findings").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(findings) { f in
                HStack {
                    Text(f.severity.uppercased()).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    VStack(alignment: .leading) {
                        Text(f.title)
                        if let loc = f.location { Text(loc).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}

struct InspectorView: View {
    var findings: [Finding]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inspector").font(.headline)
            Divider()
            FindingsView(findings: findings)
        }
        .padding()
    }
}

struct ArcSheet: View {
    var phases: [ArcPhase]
    var total: Int
    var corpus: String
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Semantic Arc — \(corpus)").font(.title2)
                Spacer()
                SheetDoneButton()
            }
            Text("Total: \(total)").foregroundStyle(.secondary)
            Divider()
            if phases.isEmpty {
                Text("No arc data")
            } else {
                Table(phases) {
                    TableColumn("Phase") { Text($0.phase) }
                    TableColumn("Weight") { Text("\($0.weight)") }
                    TableColumn("Percent") { Text("\(Int($0.pct * 100))%") }
                }.frame(minHeight: 200)
            }
            Spacer()
        }
        .padding()
    }
}

private struct SheetDoneButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Done") { dismiss() } }
}

struct Finding: Identifiable, Hashable { var id = UUID(); var title: String; var severity: String; var location: String?; var line: Int? }
struct ArcPhase: Identifiable, Hashable { var id = UUID(); var phase: String; var weight: Int; var pct: Double }
