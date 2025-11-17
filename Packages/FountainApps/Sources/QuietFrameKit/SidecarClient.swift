import Foundation

public actor QuietFrameSidecarClient {
    public struct Config {
        public var baseURL: URL
        public var targetDisplayName: String?
        public var targetInstanceId: String?
        public init(baseURL: URL = URL(string: ProcessInfo.processInfo.environment["MVK_RUNTIME_URL"] ?? "http://127.0.0.1:7777")!,
                    targetDisplayName: String? = nil,
                    targetInstanceId: String? = nil) {
            self.baseURL = baseURL
            self.targetDisplayName = targetDisplayName
            self.targetInstanceId = targetInstanceId
        }
    }

    public var onUMP: (@Sendable ([UInt32]) -> Void)? = nil
    private let cfg: Config
    private var sinceNs: String? = nil
    private var pollingTask: Task<Void, Never>? = nil

    public init(config: Config = .init()) {
        self.cfg = config
    }

    deinit { pollingTask?.cancel() }

    // MARK: - Control
    public func startPolling(pollIntervalMs: Int = 100) {
        pollingTask?.cancel()
        pollingTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(max(10, pollIntervalMs)) * 1_000_000)
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func setUMPSink(_ sink: @escaping @Sendable ([UInt32]) -> Void) {
        self.onUMP = sink
    }

    // MARK: - Senders
    public func sendVendor(topic: String, data: [String: Any] = [:]) async {
        let url = url("/v1/midi/vendor", query: query())
        var body: [String: Any] = ["topic": topic]
        if !data.isEmpty { body["data"] = data }
        await postJSON(url, json: body)
    }

    public func injectSysEx7(bytes: [UInt8]) async {
        let words = QFUMP.packSysEx7(bytes)
        await injectUMP(words: words)
    }

    public func injectUMP(words: [UInt32]) async {
        let url = url("/v1/midi/events", query: query())
        var packet: [String: Any] = ["w0": Int(words[0])]
        if words.count > 1 { packet["w1"] = Int(words[1]) }
        if words.count > 2 { packet["w2"] = Int(words[2]) }
        if words.count > 3 { packet["w3"] = Int(words[3]) }
        let event: [String: Any] = ["tNs": "0", "packet": packet]
        let json: [String: Any] = ["timeDomain": "relativeToNow", "events": [event]]
        await postJSON(url, json: json)
    }

    // MARK: - Poller
    private func pollOnce() async {
        var comps = URLComponents(url: url("/v1/midi/vendor"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let q = query() { items.append(contentsOf: q.map { URLQueryItem(name: $0.key, value: $0.value) }) }
        if let sinceNs { items.append(URLQueryItem(name: "sinceNs", value: sinceNs)) }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let events = obj["events"] as? [[String: Any]] else { return }
            for ev in events {
                if let t = ev["tNs"] as? String { sinceNs = t }
                guard let pkt = ev["packet"] as? [String: Any], let w0 = pkt["w0"] as? Int else { continue }
                var words: [UInt32] = [UInt32(truncatingIfNeeded: w0)]
                if let w1 = pkt["w1"] as? Int { words.append(UInt32(truncatingIfNeeded: w1)) }
                if let w2 = pkt["w2"] as? Int { words.append(UInt32(truncatingIfNeeded: w2)) }
                if let w3 = pkt["w3"] as? Int { words.append(UInt32(truncatingIfNeeded: w3)) }
                if let cb = onUMP { cb(words) }
            }
        } catch {
            // Ignore transient errors
        }
    }

    // MARK: - HTTP helpers
    private func url(_ path: String, query: [String: String]? = nil) -> URL {
        var comps = URLComponents(url: cfg.baseURL, resolvingAgainstBaseURL: false)!
        comps.path = path
        if let query { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return comps.url!
    }

    private func query() -> [String: String]? {
        var q: [String: String] = [:]
        if let id = cfg.targetInstanceId { q["targetInstanceId"] = id }
        if let name = cfg.targetDisplayName { q["targetDisplayName"] = name }
        return q.isEmpty ? nil : q
    }

    private func postJSON(_ url: URL, json: [String: Any]) async {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        _ = try? await URLSession.shared.data(for: req)
    }
}
