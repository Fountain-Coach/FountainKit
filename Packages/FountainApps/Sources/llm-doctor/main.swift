import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct LLMDoctor {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let endpointEnv = env["ENGRAVER_LOCAL_LLM_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferJSON = (env["LLM_DOCTOR_JSON"]?.lowercased() == "1") || CommandLine.arguments.contains("--json")
        let timeoutSec: TimeInterval = parseTimeout(from: env) ?? 2.5

        // Candidate endpoints (OpenAI-compatible first)
        var candidates: [Probe] = []
        if let endpointEnv, let url = URL(string: endpointEnv) {
            candidates.append(.openAICompat(url))
        }
        // Common OpenAI-compatible servers
        candidates.append(.openAICompat(URL(string: "http://127.0.0.1:11434")!)) // Ollama recent OpenAI compat
        candidates.append(.openAICompat(URL(string: "http://127.0.0.1:8000")!))  // vLLM default
        // Ollama classic API
        candidates.append(.ollama(URL(string: "http://127.0.0.1:11434")!))
        // LocalAgent health
        candidates.append(.localAgent(URL(string: "http://127.0.0.1:8080")!))

        var found: Result? = nil
        for probe in candidates {
            if let res = await runProbe(probe, timeout: timeoutSec) {
                found = res; break
            }
        }

        if preferJSON {
            if let found {
                printJSON(["ok": true, "provider": found.provider, "url": found.url.absoluteString, "details": found.details])
                exit(0)
            } else {
                printJSON(["ok": false, "error": "No local LLM endpoint detected", "checked": candidates.map { $0.describe }])
                exit(1)
            }
        } else {
            if let found {
                print("Local LLM detected: \(found.provider) @ \(found.url.absoluteString)")
                if let details = found.details, !details.isEmpty { print("Details: \(details)") }
                exit(0)
            } else {
                fputs("No local LLM endpoint detected. Tried: \n\(candidates.map { " - \($0.describe)" }.joined(separator: "\n"))\n", stderr)
                print("Hint: set ENGRAVER_LOCAL_LLM_URL to an OpenAI-compatible endpoint, or start Ollama/vLLM/LocalAgent.")
                exit(1)
            }
        }
    }

    // MARK: - Models
    enum Probe {
        case openAICompat(URL)
        case ollama(URL)
        case localAgent(URL)
        var describe: String {
            switch self {
            case .openAICompat(let base): return "OpenAI-compatible at \(base.host ?? "?"):\(base.port.map(String.init) ?? "(default)")"
            case .ollama(let base): return "Ollama classic at \(base.host ?? "?"):\(base.port.map(String.init) ?? "(default)")"
            case .localAgent(let base): return "LocalAgent health at \(base.host ?? "?"):\(base.port.map(String.init) ?? "(default)")"
            }
        }
    }

    struct Result { let provider: String; let url: URL; let details: String? }

    // MARK: - Probes
    static func runProbe(_ probe: Probe, timeout: TimeInterval) async -> Result? {
        switch probe {
        case .openAICompat(let base):
            // Try GET /v1/models
            if let url = URL(string: "/v1/models", relativeTo: ensureBase(base)) {
                if let json = await fetchJSON(url: url, timeout: timeout), let dict = json as? [String: Any], let data = dict["data"] as? [Any] {
                    return Result(provider: "openai-compatible", url: ensureBase(base), details: "models=\(data.count)")
                }
            }
            return nil
        case .ollama(let base):
            if let url = URL(string: "/api/tags", relativeTo: ensureBase(base)) {
                if let json = await fetchJSON(url: url, timeout: timeout) {
                    if let dict = json as? [String: Any], let models = dict["models"] as? [Any] {
                        return Result(provider: "ollama", url: ensureBase(base), details: "models=\(models.count)")
                    }
                    if let arr = json as? [Any] { // some versions return array
                        return Result(provider: "ollama", url: ensureBase(base), details: "models=\(arr.count)")
                    }
                }
            }
            return nil
        case .localAgent(let base):
            if let url = URL(string: "/health", relativeTo: ensureBase(base)) {
                if let json = await fetchJSON(url: url, timeout: timeout) {
                    if let dict = json as? [String: Any] {
                        let ok = (dict["ok"] as? Bool) ?? (dict["healthy"] as? Bool) ?? false
                        if ok { return Result(provider: "local-agent", url: ensureBase(base), details: nil) }
                    }
                }
            }
            return nil
        }
    }

    static func ensureBase(_ url: URL) -> URL {
        // Strip known OpenAI chat path if present
        if url.path.hasSuffix("/v1/chat/completions") {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            c.path = ""
            return c.url!
        }
        return url
    }

    // MARK: - HTTP
    static func fetchJSON(url: URL, timeout: TimeInterval) async -> Any? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = timeout
        do {
            #if canImport(FoundationNetworking)
            let (data, resp) = try await URLSession.shared.data(for: req)
            #else
            let (data, resp) = try await URLSession.shared.data(for: req)
            #endif
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch { return nil }
    }

    // MARK: - Utils
    static func printJSON(_ obj: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]), let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            print("{\"ok\":false,\"error\":\"encoding\"}")
        }
    }

    static func parseTimeout(from env: [String: String]) -> TimeInterval? {
        if let raw = env["LLM_DOCTOR_TIMEOUT"], let val = Double(raw), val > 0 { return val }
        if let idx = CommandLine.arguments.firstIndex(of: "--timeout"), idx + 1 < CommandLine.arguments.count, let val = Double(CommandLine.arguments[idx + 1]), val > 0 { return val }
        return nil
    }
}
