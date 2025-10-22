import Foundation

struct SpecItem: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
}

extension LauncherViewModel {
    func curatedSpecs() -> [SpecItem] {
        guard let repo = repoPath else { return [] }
        let configURL = URL(fileURLWithPath: repo).appendingPathComponent("Configuration/curated-openapi-specs.json")
        guard let data = try? Data(contentsOf: configURL) else { return [] }
        struct Entry: Decodable { let name: String; let path: String }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.compactMap { e in
            let u = URL(fileURLWithPath: repo).appendingPathComponent(e.path)
            return SpecItem(name: e.name, url: u)
        }
    }

    func readSpec(at url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        if let data = try? Data(contentsOf: resolved), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return ""
    }

    func writeSpec(at url: URL, content: String) {
        let resolved = url.resolvingSymlinksInPath()
        do {
            try content.write(to: resolved, atomically: true, encoding: .utf8)
        } catch {
            Task { @MainActor in self.errorMessage = "Save failed: \(String(describing: error))" }
        }
    }

    func lintSpec(at url: URL) {
        guard let repo = repoPath else { return }
        runStreaming(command: ["bash", "Scripts/openapi-lint.sh"], cwd: repo, env: processEnv())
    }

    func regenerateFromSpecs() {
        guard let repo = repoPath else { return }
        runStreaming(command: ["swift", "build"], cwd: repo, env: processEnv())
    }

    func reloadGatewayRoutes() {
        let defaultsURL = defaultsString("FountainAI.GATEWAY_URL", fallback: "http://127.0.0.1:8010")
        guard let base = URL(string: defaultsURL) else { return }
        var url = base; url.append(path: "/admin/reload")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let bearer = KeychainHelper.read(service: "FountainAI", account: "GATEWAY_BEARER"), !bearer.isEmpty {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: req) { _, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            Task { @MainActor in
                if let err { self.errorMessage = "Reload failed: \(err.localizedDescription)" }
                else if code != 200 && code != 204 { self.errorMessage = "Reload returned status \(code)" }
            }
        }.resume()
    }
}
