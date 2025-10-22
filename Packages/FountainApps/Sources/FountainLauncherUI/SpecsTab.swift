import SwiftUI
import AppKit

struct SpecsTab: View {
    @ObservedObject var vm: LauncherViewModel
    @State private var selected: SpecItem? = nil
    @State private var specs: [SpecItem] = []
    @State private var filter: String = ""

    var body: some View {
        ThreePane(leftWidth: 300, rightWidth: 340) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OpenAPI Specs").font(.headline)
                    Spacer()
                    Button("Refresh") { specs = vm.findSpecs() }
                }
                TextField("Filter", text: $filter)
                List(selection: Binding(get: { selected }, set: { selected = $0 })) {
                    ForEach(specs.filter { filter.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(filter) }) { item in
                        HStack {
                            Image(systemName: "doc.text")
                            Text(item.name)
                        }.tag(item as SpecItem?)
                    }
                }
            }
            .padding(12)
            .onAppear { specs = vm.findSpecs() }
        } middle: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(selected?.name ?? "No spec selected").font(.headline)
                    Spacer()
                    if let u = selected?.url { Button("Open in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
                }
                ScrollView {
                    Text(selected.flatMap { vm.readSpec(at: $0.url) } ?? "")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .padding(12)
        } right: {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox(label: Text("Pipeline")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Lint") { if let u = selected?.url { vm.lintSpec(at: u) } }
                        Button("Regenerate Types") { vm.regenerateFromSpecs() }
                        Button("Precompile Full Stack") { vm.precompileFullStack() }
                        Button("Reload Gateway Routes") { vm.reloadGatewayRoutes() }
                    }
                }
                GroupBox(label: Text("Notes")) {
                    Text("Pipeline: Lint → Generate → Precompile → Reload.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
        }
    }
}

struct SpecItem: Identifiable, Hashable { let id = UUID(); let url: URL; var name: String { url.lastPathComponent } }

extension LauncherViewModel {
    func findSpecs() -> [SpecItem] {
        guard let repoPath else { return [] }
        let fm = FileManager.default
        var results: [SpecItem] = []
        let roots = ["Packages/FountainSpecCuration/openapi", "Packages"]
        for root in roots {
            let base = URL(fileURLWithPath: repoPath).appendingPathComponent(root)
            guard let en = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let u as URL in en {
                if u.pathExtension.lowercased() == "yaml" || u.pathExtension.lowercased() == "yml" {
                    results.append(SpecItem(url: u))
                } else if u.lastPathComponent == "openapi.yaml" {
                    results.append(SpecItem(url: u))
                }
            }
        }
        return Array(Set(results)).sorted(by: { $0.name < $1.name })
    }

    func readSpec(at url: URL) -> String {
        (try? String(contentsOf: url)) ?? ""
    }

    func lintSpec(at url: URL) {
        guard let repoPath else { return }
        if FileManager.default.fileExists(atPath: URL(fileURLWithPath: repoPath).appendingPathComponent("Scripts/openapi-lint.sh").path) {
            runStreaming(command: ["bash", "Scripts/openapi-lint.sh", url.path], cwd: repoPath, env: processEnv())
        } else {
            logText += "\n[specs] Lint: script not found, skipping.\n"
        }
    }

    func regenerateFromSpecs() {
        // Generators run as part of swift build; build FountainApps to trigger all plugins
        guard let repoPath else { return }
        runStreaming(command: ["swift", "build", "--configuration", "debug", "--package-path", "Packages/FountainApps"], cwd: repoPath, env: processEnv())
    }

    func reloadGatewayRoutes() {
        // POST /admin/routes/reload
        let url = URL(string: "http://127.0.0.1:8010/admin/routes/reload")!
        var req = URLRequest(url: url); req.httpMethod = "POST"
        if let bearer = KeychainHelper.read(service: "FountainAI", account: "GATEWAY_BEARER"), !bearer.isEmpty {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
        logText += "\n[specs] Requested gateway route reload.\n"
    }
}

