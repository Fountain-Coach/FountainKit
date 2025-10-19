import Foundation
import ApiClientsCore
import FountainAIKit

struct LearnSiteCrawler: Sendable {
    struct Options: Sendable {
        var mode: SeedingConfiguration.Browser.Mode = .standard
        var pagesLimit: Int = 12
        var maxDepth: Int = 2
        var sameHostOnly: Bool = true
        var defaultLabels: [String] = []
        var pagesCollection: String = "pages"
        var segmentsCollection: String = "segments"
        var entitiesCollection: String = "entities"
        var tablesCollection: String = "tables"
    }

    struct Coverage: Sendable {
        let visited: Int
        let pagesIndexed: Int
        let segmentsIndexed: Int
    }

    func learn(
        seed: URL,
        semanticBrowserURL: URL,
        corpusId: String,
        options: Options,
        log: @Sendable (String) -> Void,
        progress: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> Coverage {
        // Use a session with longer resource timeout to accommodate real page rendering
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 180
        let http = RESTClient(baseURL: semanticBrowserURL, defaultHeaders: ["Accept":"application/json","Content-Type":"application/json"], session: URLSession(configuration: cfg))

        struct Q: Hashable { let url: URL; let depth: Int }
        var queue: [Q] = [Q(url: seed, depth: 0)]
        var seen = Set<String>()
        var visited = 0
        var pagesIndexed = 0
        var segmentsIndexed = 0

        while !queue.isEmpty {
            if visited >= options.pagesLimit { break }
            let item = queue.removeFirst()
            let url = item.url
            if options.sameHostOnly && url.host != seed.host { continue }
            if seen.contains(url.absoluteString) { continue }
            seen.insert(url.absoluteString)

            // Prepare browse request
            do {
                // Build /v1/browse request body matching the current OpenAPI shape
                let wait: [String: Any] = [
                    "strategy": "domContentLoaded",
                    "maxWaitMs": 20000
                ]
                let mode: String = {
                    switch options.mode { case .quick: return "quick"; case .deep: return "deep"; default: return "standard" }
                }()
                let indexObj: [String: Any] = [
                    "enabled": true,
                    "pagesCollection": options.pagesCollection,
                    "segmentsCollection": options.segmentsCollection,
                    "entitiesCollection": options.entitiesCollection,
                    "tablesCollection": options.tablesCollection
                ]
                let labels = options.defaultLabels + (seed.host.map { [$0] } ?? [])
                let body: [String: Any] = [
                    "url": url.absoluteString,
                    "wait": wait,
                    "mode": mode,
                    "index": indexObj,
                    "storeArtifacts": true,
                    "labels": labels
                ]
                let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                guard let reqURL = http.buildURL(path: "/v1/browse") else { continue }
                let resp = try await http.send(APIRequest(method: .POST, url: reqURL, headers: [:], body: data))
                let obj = try JSONSerialization.jsonObject(with: resp.data) as? [String: Any]
                if let idx = obj?["index"] as? [String: Any] {
                    pagesIndexed += (idx["pagesUpserted"] as? Int) ?? 0
                    segmentsIndexed += (idx["segmentsUpserted"] as? Int) ?? 0
                } else if let analysis = obj?["analysis"] as? [String: Any] {
                    // Perform explicit indexing when browse response didn't include index metrics
                    let body: [String: Any] = [
                        "analysis": analysis,
                        "options": ["enabled": true]
                    ]
                    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                    if let url = http.buildURL(path: "/v1/index") {
                        do {
                            let r2 = try await http.send(APIRequest(method: .POST, url: url, headers: [:], body: data))
                            if let idx2 = try JSONSerialization.jsonObject(with: r2.data) as? [String: Any] {
                                pagesIndexed += (idx2["pagesUpserted"] as? Int) ?? 0
                                segmentsIndexed += (idx2["segmentsUpserted"] as? Int) ?? 0
                            }
                        } catch { /* ignore and continue */ }
                    }
                }
                visited += 1
                progress?(visited, pagesIndexed, segmentsIndexed)

                // Extract links for crawl
                // Fetch snapshot HTML for link extraction via export endpoint. If fails, continue.
                if item.depth < options.maxDepth {
                    do {
                        // Pragmatic alternative: re-fetch HTML directly and parse links.
                        let (data, response) = try await URLSession.shared.data(from: url)
                        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let html = String(data: data, encoding: .utf8) {
                            let links = Self.extractLinks(html: html, base: url)
                            for u in links { queue.append(Q(url: u, depth: item.depth + 1)) }
                        }
                    } catch { /* ignore link extraction failure */ }
                }
                log("learn: indexed \(url.absoluteString)")
            } catch {
                log("learn: error • \(url.absoluteString) • \(error)")
                progress?(visited, pagesIndexed, segmentsIndexed)
            }
        }

        return Coverage(visited: visited, pagesIndexed: pagesIndexed, segmentsIndexed: segmentsIndexed)
    }

    private static func extractLinks(html: String, base: URL) -> [URL] {
        let pattern = "href=\\\"([^\\\"]+)\\\"|href='([^']+)'"
        var out: [URL] = []
        if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let ns = html as NSString
            for m in rx.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let r1 = m.range(at: 1); let r2 = m.range(at: 2)
                let raw: String
                if r1.location != NSNotFound { raw = ns.substring(with: r1) }
                else if r2.location != NSNotFound { raw = ns.substring(with: r2) }
                else { continue }
                if raw.hasPrefix("#") { continue }
                guard let u = URL(string: raw, relativeTo: base)?.absoluteURL else { continue }
                if filterCrawlable(u) { out.append(u) }
            }
        }
        return out
    }

    private static func filterCrawlable(_ u: URL) -> Bool {
        let badExt: Set<String> = ["css","js","png","jpg","jpeg","gif","svg","ico","webp","mp4","mp3","mov","pdf","zip","tar","gz","7z","rar","woff","woff2","ttf"]
        if let scheme = u.scheme?.lowercased(), !(scheme == "http" || scheme == "https") { return false }
        let ext = u.pathExtension.lowercased()
        if !ext.isEmpty && badExt.contains(ext) { return false }
        let path = u.path.lowercased()
        if path.contains("/assets/") { return false }
        let banned = ["impressum","hilfe","help","support","kontakt","contact","privacy","datenschutz","about","agb","terms","imprint"]
        if banned.contains(where: { path.contains($0) }) { return false }
        return true
    }
}
