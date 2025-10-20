import SwiftUI
import Foundation
import SemanticBrowserAPI
import OpenAPIRuntime
import OpenAPIURLSession
import FountainRuntime

#if canImport(WebKit)
import WebKit
struct _WKView: NSViewRepresentable {
    let url: URL?
    let webView = WKWebView()
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {
        if let u = url { view.load(URLRequest(url: u)) }
    }
}
#endif

/// Minimal in‑app visual browser: shows a URL like a browser and overlays
/// the captured evidence map next to it. Use with a MemChatController so the
/// view can classify covered/missing against stored evidence.
public struct VisualBrowserView: View {
    public init(controller: MemChatController) { self.controller = controller }

    private let controller: MemChatController
    @State private var urlString: String = "https://"
    @State private var liveURL: URL? = nil
    @State private var loading: Bool = false
    @State private var status: String = ""
    @State private var imageURL: URL? = nil
    @State private var covered: [EvidenceMapView.Overlay] = []
    @State private var missing: [EvidenceMapView.Overlay] = []
    @State private var stale: [EvidenceMapView.Overlay] = []
    @State private var coverage: Double = 0
    @State private var serverClassify: Bool = true
    @State private var staleDays: Int = 60
    @State private var lastAnalysis: SemanticBrowserAPI.Components.Schemas.Analysis? = nil
    @State private var lastImageId: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Visual Browser").font(.headline)
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("https://…", text: $urlString).textFieldStyle(.roundedBorder)
                Button("Go") { if let u = URL(string: urlString) { liveURL = u } }
                Button(loading ? "Capturing…" : "Capture Map") { Task { await capture() } }.disabled(loading)
                Button("Index Page") { Task { await indexLast() } }.disabled(lastAnalysis == nil)
            }
            .padding(.bottom, 4)
            HStack(spacing: 12) {
                #if canImport(WebKit)
                _WKView(url: liveURL)
                    .frame(minWidth: 380, minHeight: 420)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
                #endif
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Picker("Stale", selection: $staleDays) {
                            Text("30d").tag(30); Text("60d").tag(60); Text("90d").tag(90)
                        }.pickerStyle(.segmented).frame(width: 200)
                        Toggle("Server Covered", isOn: $serverClassify).toggleStyle(.switch)
                        Spacer()
                    }
                    EvidenceMapView(
                        title: "Captured Map",
                        imageURL: imageURL,
                        covered: covered,
                        stale: stale,
                        missing: missing,
                        initialCoverage: coverage,
                        onSelect: { _ in }
                    )
                }
            }
        }
        .padding(8)
    }

    private func semanticBrowserClient() -> (base: URL, client: SemanticBrowserAPI.Client) {
        let base = URL(string: ProcessInfo.processInfo.environment["SEMANTIC_BROWSER_URL"] ?? "http://127.0.0.1:8007")!
        var defaultHeaders: [String: String] = [:]
        if let key = ProcessInfo.processInfo.environment["SEMANTIC_BROWSER_API_KEY"], !key.isEmpty { defaultHeaders["X-API-Key"] = key }
        let (transport, middlewares) = OpenAPIClientFactory.makeURLSessionTransport(defaultHeaders: defaultHeaders)
        return (base, SemanticBrowserAPI.Client(serverURL: base, transport: transport, middlewares: middlewares))
    }

    private func capture() async {
        guard let u = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { status = "Invalid URL"; return }
        loading = true
        status = "Capturing…"
        defer { loading = false }
        let (base, client) = semanticBrowserClient()
        let wait = SemanticBrowserAPI.Components.Schemas.WaitPolicy(strategy: .networkIdle, networkIdleMs: 500, selector: nil, maxWaitMs: 14000)
        let req = SemanticBrowserAPI.Components.Schemas.BrowseRequest(url: u.absoluteString, wait: wait, mode: .standard, index: .init(enabled: false), storeArtifacts: false, labels: nil)
        do {
            let out = try await client.browseAndDissect(.init(body: .json(req)))
            guard case .ok(let ok) = out else { status = "Capture failed"; return }
            let body = try ok.body.json
            lastAnalysis = body.analysis
            if let img = body.snapshot.rendered.image, let iid = img.imageId { lastImageId = iid; imageURL = base.appendingPathComponent("assets/").appendingPathComponent("\(iid).png") }
            // Build overlays and optional server classification
            if let analysis = body.analysis, let iid = lastImageId {
                let texts = await controller.evidencePreview(host: u.host ?? "", depthLevel: controller.config.depthLevel).map { $0.text }
                let groups = VisualDiffBuilder.classify(analysis: analysis, imageId: iid, evidenceTexts: texts, minOverlap: 0.18)
                await MainActor.run {
                    covered = groups.covered
                    missing = groups.missing
                    stale = []
                    coverage = Double(VisualCoverageUtils.unionAreaNormalized(groups.covered.map { $0.rect }))
                    status = "Captured ✓"
                }
            } else { status = "No analysis available" }
        } catch { status = "Capture error: \(error.localizedDescription)" }
    }

    private func indexLast() async {
        guard let analysis = lastAnalysis else { status = "Nothing to index"; return }
        let (_, client) = semanticBrowserClient()
        do {
            let req = SemanticBrowserAPI.Components.Schemas.IndexRequest(analysis: analysis, options: nil)
            let out = try await client.indexAnalysis(.init(body: .json(req)))
            guard case .ok = out else { status = "Index failed"; return }
            status = "Indexed ✓"
        } catch { status = "Index error: \(error.localizedDescription)" }
    }
}
