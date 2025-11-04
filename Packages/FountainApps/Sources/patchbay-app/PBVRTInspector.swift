import SwiftUI
import AVKit
import AppKit
import FountainStoreClient

struct PBVRTInspector: View {
    @State private var corpusId: String = "pb-vrt"
    @State private var baselines: [String] = []
    @State private var selectedBaseline: String = ""
    @State private var summaryLines: [String] = []
    @State private var artifactsDir: URL? = nil
    @State private var demoGIF: URL? = nil
    @State private var demoMP4: URL? = nil
    @State private var baselinePNG: URL? = nil
    @State private var candidatePNG: URL? = nil
    @State private var alignedPNG: URL? = nil
    @State private var deltaPNG: URL? = nil
    @State private var salBaselinePNG: URL? = nil
    @State private var salCandidatePNG: URL? = nil
    @State private var salWeightedPNG: URL? = nil
    @State private var specBaselinePNG: URL? = nil
    @State private var specCandidatePNG: URL? = nil
    @State private var specDeltaPNG: URL? = nil
    @State private var isLoading: Bool = false
    @State private var askText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("PB‑VRT").font(.headline)
                Spacer()
                Button {
                    refreshList()
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(isLoading)
            }

            HStack(spacing: 8) {
                Text("Corpus:")
                TextField("pb-vrt", text: $corpusId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Text("Baseline:")
                Picker("Baseline", selection: $selectedBaseline) {
                    ForEach(baselines, id: \.self) { id in Text(id).tag(id) }
                }
                .onChange(of: selectedBaseline) { _ in loadSelected() }
                Spacer()
                if let dir = artifactsDir {
                    Button { NSWorkspace.shared.open(dir) } label: { Label("Open Artifacts", systemImage: "folder") }
                }
            }

            // Quick Actions
            HStack(spacing: 10) {
                Button { startServer() } label: { Label("Start Server", systemImage: "play.circle") }
                Button { seedBaselineFromPNG() } label: { Label("Seed Baseline", systemImage: "tray.and.arrow.down") }
                    .disabled(isLoading)
                Button { runCompareWithCandidatePNG() } label: { Label("Run Compare", systemImage: "checkmark.circle") }
                    .disabled(selectedBaseline.isEmpty)
                Button { composePresentation() } label: { Label("Compose Clip", systemImage: "film") }
                    .disabled(selectedBaseline.isEmpty)
            }
            .padding(.vertical, 2)

            TabView {
                guideTab()
                    .tabItem { Label("Guide", systemImage: "questionmark.circle") }
                askTab()
                    .tabItem { Label("Ask", systemImage: "person.and.questionmark") }
                summaryTab()
                    .tabItem { Label("Summary", systemImage: "checkmark.seal") }

                visionTab()
                    .tabItem { Label("Vision", systemImage: "viewfinder") }

                audioTab()
                    .tabItem { Label("Audio", systemImage: "waveform") }

                clipTab()
                    .tabItem { Label("Clip", systemImage: "film") }
            }
            .frame(minHeight: 380)
        }
        .padding(12)
        .onAppear { refreshList() }
    }

    @ViewBuilder
    private func guideTab() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("PB‑VRT — What you’re seeing")
                    .font(.headline)
                Text("The canvas shows the story as a small patch: Baseline on the left; Compare, Align, Saliency, and Audio in the middle; Present on the right. The noodles express how one step feeds the next.")
                    .fixedSize(horizontal: false, vertical: true)
                if selectedBaseline.isEmpty {
                    Text("No baseline selected. Seed one to start.").foregroundColor(.secondary)
                } else {
                    Text("Selected baseline: \(selectedBaseline)").font(.subheadline)
                }
                HStack(spacing: 10) {
                    Button { startServer() } label: { Label("Start Server", systemImage: "play.circle") }
                    Button { seedBaselineFromPNG() } label: { Label("Create Baseline", systemImage: "tray.and.arrow.down") }
                    Button { runCompareWithCandidatePNG() } label: { Label("Run Compare", systemImage: "checkmark.circle") }
                    Button { composePresentation() } label: { Label("Make Presentation", systemImage: "film") }
                }
                .padding(.top, 4)
                Divider()
                Text("Tip: Use Canvas → Insert PB‑VRT Story Patch to place the graph if the canvas is empty.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func askTab() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask the Assistant").font(.headline)
            HStack(spacing: 8) {
                Button("Explain Last Run") { Task { await explainLastRun() } }
                Button("Why Failed?") { Task { await explainLastRun(focusFailures: true) } }
                Button("How to Fix") { askText = suggestedFix() }
            }
            TextEditor(text: $askText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .border(Color.gray.opacity(0.2))
        }
        .padding(8)
    }

    private func suggestedFix() -> String {
        "Try Align first and re‑compare. If pixel_l1 or ssim still fail, inspect the saliency‑weighted delta. For audio, confirm lsd_db < 0.5 with matching sample rates; otherwise regenerate tones or adjust thresholds to your acceptance policy."
    }

    private func analyze(metrics: [String: Any], thresholds: (fp: Double, l1: Double, ssim: Double)) -> String {
        func val(_ k: String) -> Double? { (metrics[k] as? NSNumber)?.doubleValue ?? Double((metrics[k] as? String) ?? "") }
        let fp = val("featureprint_distance")
        let l1 = val("pixel_l1")
        let ssim = val("ssim")
        var lines: [String] = []
        lines.append("Analysis of last run:")
        if let v = fp { lines.append(String(format: "• featureprint_distance = %.4f (max %.3f) — %@", v, thresholds.fp, v <= thresholds.fp ? "ok" : "high")) }
        if let v = l1 { lines.append(String(format: "• pixel_l1 = %.4f (max %.3f) — %@", v, thresholds.l1, v <= thresholds.l1 ? "ok" : "high")) }
        if let v = ssim { lines.append(String(format: "• ssim = %.4f (min %.3f) — %@", v, thresholds.ssim, v >= thresholds.ssim ? "ok" : "low")) }
        let pass = (fp ?? 0) <= thresholds.fp && (l1 ?? .greatestFiniteMagnitude) <= thresholds.l1 && (ssim ?? 1) >= thresholds.ssim
        lines.append(pass ? "Verdict: PASS" : "Verdict: FAIL")
        return lines.joined(separator: "\n")
    }

    private func extractMetrics(from obj: [String: Any]) -> [String: Any] {
        (obj["metrics"] as? [String: Any]) ?? [:]
    }

    private func fetchCompareJSON(baselineId: String) async -> [String: Any]? {
        let store: FountainStoreClient = {
            if let disk = try? DiskFountainStoreClient(rootDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        let segId = "pbvrt:baseline:\(baselineId):pbvrt.compare"
        if let data = try? await store.getDoc(corpusId: corpusId, collection: "segments", id: segId), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return obj
        }
        return nil
    }

    private func thresholds() -> (Double, Double, Double) { (0.035, 0.012, 0.94) }

    private func updateAsk(_ text: String) { DispatchQueue.main.async { self.askText = text } }

    private func explainFromSummaryLines(focusFailures: Bool = false) {
        var metrics: [String: Any] = [:]
        for l in summaryLines {
            for k in ["featureprint_distance","pixel_l1","ssim"] {
                if l.contains(k), let v = l.split(separator: "=").last { metrics[k] = Double(v.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") ?? 0 }
            }
        }
        let txt = analyze(metrics: metrics, thresholds: thresholds())
        updateAsk(txt)
    }

    private func explainLastRun(focusFailures: Bool = false) async {
        guard !selectedBaseline.isEmpty else { updateAsk("No baseline yet — create one first."); return }
        if let obj = await fetchCompareJSON(baselineId: selectedBaseline) {
            let txt = analyze(metrics: extractMetrics(from: obj), thresholds: thresholds())
            updateAsk(txt)
        } else {
            explainFromSummaryLines(focusFailures: focusFailures)
        }
    }

    // MARK: - Actions
    private func startServer() {
        Task.detached {
            _ = PBVRT_runBash(["bash","Scripts/apps/pbvrt-up"]) // best-effort
        }
    }

    private func seedBaselineFromPNG() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["png"]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task.detached { [sel = selectedBaseline] in
                let base = PBVRT_baseURL()
                _ = PBVRT_runBash(["bash","Scripts/apps/pbvrt-baseline-seed","--png", url.path, "--server", base, "--out", "baseline.id"]) ?? ""
                DispatchQueue.main.async {
                    refreshList()
                }
            }
        }
    }

    private func runCompareWithCandidatePNG() {
        guard !selectedBaseline.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["png"]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task.detached { [id = selectedBaseline] in
                let out = PBVRT_runBash(["bash","Scripts/apps/pbvrt-compare-run","--baseline-id", id, "--candidate", url.path]) ?? ""
                DispatchQueue.main.async {
                    self.summaryLines = out.split(separator: "\n").map(String.init)
                    self.loadSelected()
                }
            }
        }
    }

    private func composePresentation() {
        guard !selectedBaseline.isEmpty else { return }
        Task.detached { [id = selectedBaseline] in
            let fm = FileManager.default
            let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
            let work = cwd.appendingPathComponent(".fountain/demos/pb-vrt/\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)
            // Emit frames + timeline
            _ = PBVRT_runBash(["python3","Scripts/apps/pbvrt-animate","--baseline-id", id, "--frames-dir", work.appendingPathComponent("frames").path, "--out", work.appendingPathComponent("demo.gif").path])
            // Build mp4 (best-effort without audio if WAVs not present)
            _ = PBVRT_runBash(["swift","run","--package-path","Packages/FountainApps","pbvrt-present","--frames-dir", work.appendingPathComponent("frames").path, "--out", work.appendingPathComponent("demo.mp4").path])
            DispatchQueue.main.async {
                self.demoGIF = work.appendingPathComponent("demo.gif")
                self.demoMP4 = work.appendingPathComponent("demo.mp4")
            }
        }
    }

    private func __remove_pbvrtBaseURL() -> String {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let portFile = cwd.appendingPathComponent(".fountain/pb-vrt-port")
        if let p = try? String(contentsOf: portFile), !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "http://127.0.0.1:\(p.trimmingCharacters(in: .whitespacesAndNewlines))/pb-vrt"
        }
        return "http://127.0.0.1:8010/pb-vrt"
    }

    @discardableResult
    private func __remove_runBash(_ argv: [String]) -> String? {
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = argv
        var env = ProcessInfo.processInfo.environment
        env["FOUNTAIN_SKIP_LAUNCHER_SIG"] = "1"
        p.environment = env
        let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    @ViewBuilder
    private func summaryTab() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if summaryLines.isEmpty { Text("No compare summary found.").foregroundColor(.secondary) }
                ForEach(summaryLines, id: \.self) { s in Text(s).font(.system(.body, design: .monospaced)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private func visionTab() -> some View {
        VStack(spacing: 8) {
            HStack {
                imageView(url: baselinePNG, label: "Baseline")
                imageView(url: candidatePNG, label: "Candidate")
            }
            HStack {
                imageView(url: alignedPNG, label: "Aligned")
                imageView(url: deltaPNG, label: "Pixel Delta")
            }
            HStack {
                imageView(url: salBaselinePNG, label: "Saliency (Baseline)")
                imageView(url: salCandidatePNG, label: "Saliency (Candidate)")
            }
            imageView(url: salWeightedPNG, label: "Saliency‑weighted Delta")
        }
    }

    @ViewBuilder
    private func audioTab() -> some View {
        VStack(spacing: 8) {
            HStack {
                imageView(url: specBaselinePNG, label: "Spectrogram (Baseline)")
                imageView(url: specCandidatePNG, label: "Spectrogram (Candidate)")
            }
            imageView(url: specDeltaPNG, label: "Spectrogram Delta")
        }
    }

    @ViewBuilder
    private func clipTab() -> some View {
        VStack(spacing: 8) {
            if let mp4 = demoMP4 {
                PBVideoPlayer(url: mp4)
                    .frame(minHeight: 220)
            } else if let gif = demoGIF {
                if let nsimg = NSImage(contentsOf: gif) {
                    Image(nsImage: nsimg)
                        .resizable().scaledToFit()
                        .border(Color.gray.opacity(0.3))
                }
            } else {
                Text("No clip yet. Use PB‑VRT demo/animate to compose one.").foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func imageView(url: URL?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            ZStack {
                Rectangle().fill(Color(NSColor.windowBackgroundColor))
                if let u = url, let img = NSImage(contentsOf: u) {
                    Image(nsImage: img).resizable().scaledToFit()
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 120)
            .border(Color.gray.opacity(0.2))
        }
    }

    private func refreshList() {
        isLoading = true
        defer { isLoading = false }
        // Discover baselines from artifacts directory for now
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let root = cwd.appendingPathComponent(".fountain/artifacts/pb-vrt", isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        let ids = children.filter { $0.lastPathComponent != "ad-hoc" }.map { $0.lastPathComponent }.sorted()
        baselines = ids
        if selectedBaseline.isEmpty, let last = ids.last { selectedBaseline = last }
        loadSelected()
    }

    private func loadSelected() {
        guard !selectedBaseline.isEmpty else { return }
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let dir = cwd.appendingPathComponent(".fountain/artifacts/pb-vrt/\(selectedBaseline)", isDirectory: true)
        artifactsDir = dir
        baselinePNG = dir.appendingPathComponent("baseline.png")
        candidatePNG = dir.appendingPathComponent("candidate.png")
        let deltaFull = dir.appendingPathComponent("delta_full.png")
        let deltaSmall = dir.appendingPathComponent("delta.png")
        deltaPNG = fm.fileExists(atPath: deltaFull.path) ? deltaFull : (fm.fileExists(atPath: deltaSmall.path) ? deltaSmall : nil)
        demoGIF = dir.appendingPathComponent("demo.gif")
        demoMP4 = dir.appendingPathComponent("demo.mp4")
        // ad‑hoc overlays: take latest
        let adhoc = cwd.appendingPathComponent(".fountain/artifacts/pb-vrt/ad-hoc", isDirectory: true)
        alignedPNG = latest(in: adhoc, named: "aligned.png")
        salBaselinePNG = latest(in: adhoc, named: "baseline-saliency.png")
        salCandidatePNG = latest(in: adhoc, named: "candidate-saliency.png")
        salWeightedPNG = latest(in: adhoc, named: "weighted-delta.png")
        specBaselinePNG = latest(in: dir, named: "baseline_spec.png") ?? latest(in: adhoc, named: "baseline_spec.png")
        specCandidatePNG = latest(in: dir, named: "candidate_spec.png") ?? latest(in: adhoc, named: "candidate_spec.png")
        specDeltaPNG = latest(in: dir, named: "delta_spec.png") ?? latest(in: adhoc, named: "delta_spec.png")
        Task { await loadSummary(corpus: corpusId, baselineId: selectedBaseline) }
    }

    private func latest(in folder: URL, named: String) -> URL? {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        let dated = children.compactMap { sub -> (Date, URL)? in
            let p = sub.appendingPathComponent(named)
            guard fm.fileExists(atPath: p.path) else { return nil }
            let d = (try? p.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (d, p)
        }
        return dated.sorted { $0.0 < $1.0 }.last?.1
    }

    private func loadSummary(corpus: String, baselineId: String) async {
        let store: FountainStoreClient = {
            if let disk = try? DiskFountainStoreClient(rootDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".fountain/store", isDirectory: true)) { return FountainStoreClient(client: disk) }
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }()
        let segId = "pbvrt:baseline:\(baselineId):pbvrt.compare"
        if let data = try? await store.getDoc(corpusId: corpus, collection: "segments", id: segId), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var lines: [String] = []
            if let metrics = obj["metrics"] as? [String: Any] {
                for k in ["featureprint_distance","pixel_l1","ssim"] { if let v = metrics[k] { lines.append(String(format: "%@ = %@", k, String(describing: v))) } }
            }
            if let art = obj["artifacts"] as? [String: Any] {
                for (k,v) in art { lines.append("artifacts.\(k) = \(v)") }
            }
            await MainActor.run { summaryLines = lines }
        } else {
            await MainActor.run { summaryLines = [] }
        }
    }
}

struct PBVRTInspectorHost: View {
    @State private var show: Bool = true
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PB‑VRT").font(.title3).bold()
                Spacer()
                Button { show.toggle() } label: { Image(systemName: show ? "chevron.right.square" : "chevron.left.square") }
            }
            .padding(.vertical, 6)
            Divider()
            if show { PBVRTInspector() } else { Text("PB‑VRT hidden").foregroundColor(.secondary).padding() }
        }
        .frame(minWidth: 360)
    }
}


// MARK: - Unisolated helpers for tasks
@discardableResult
func PBVRT_runBash(_ argv: [String]) -> String? {
    let p = Process()
    p.launchPath = "/usr/bin/env"
    p.arguments = argv
    var env = ProcessInfo.processInfo.environment
    env["FOUNTAIN_SKIP_LAUNCHER_SIG"] = "1"
    p.environment = env
    let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

func PBVRT_baseURL() -> String {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let portFile = cwd.appendingPathComponent(".fountain/pb-vrt-port")
    if let p = try? String(contentsOf: portFile), !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "http://127.0.0.1:\(p.trimmingCharacters(in: .whitespacesAndNewlines))/pb-vrt"
    }
    return "http://127.0.0.1:8010/pb-vrt"
}
