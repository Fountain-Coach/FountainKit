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

    // MARK: - Actions
    private func startServer() {
        Task.detached {
            _ = runBash(["bash","Scripts/apps/pbvrt-up"]) // best-effort
        }
    }

    private func seedBaselineFromPNG() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["png"]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task.detached { [sel = selectedBaseline] in
                let base = pbvrtBaseURL()
                let out = runBash(["bash","Scripts/apps/pbvrt-baseline-seed","--png", url.path, "--server", base, "--out", "baseline.id"]) ?? ""
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
                let out = runBash(["bash","Scripts/apps/pbvrt-compare-run","--baseline-id", id, "--candidate", url.path]) ?? ""
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
            _ = runBash(["python3","Scripts/apps/pbvrt-animate","--baseline-id", id, "--frames-dir", work.appendingPathComponent("frames").path, "--out", work.appendingPathComponent("demo.gif").path])
            // Build mp4 (best-effort without audio if WAVs not present)
            _ = runBash(["swift","run","--package-path","Packages/FountainApps","pbvrt-present","--frames-dir", work.appendingPathComponent("frames").path, "--out", work.appendingPathComponent("demo.mp4").path])
            DispatchQueue.main.async {
                self.demoGIF = work.appendingPathComponent("demo.gif")
                self.demoMP4 = work.appendingPathComponent("demo.mp4")
            }
        }
    }

    private func pbvrtBaseURL() -> String {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let portFile = cwd.appendingPathComponent(".fountain/pb-vrt-port")
        if let p = try? String(contentsOf: portFile), !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "http://127.0.0.1:\(p.trimmingCharacters(in: .whitespacesAndNewlines))/pb-vrt"
        }
        return "http://127.0.0.1:8010/pb-vrt"
    }

    @discardableResult
    private func runBash(_ argv: [String]) -> String? {
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
                VideoPlayer(player: AVPlayer(url: mp4))
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
