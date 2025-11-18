import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
class SSEClient: NSObject, @preconcurrency URLSessionDataDelegate {
    fileprivate let url: URL
    fileprivate var task: URLSessionDataTask?
    fileprivate var received = Data()
    fileprivate var attempt = 0
    fileprivate let maxBackoff: TimeInterval = 10

    init(url: URL) { self.url = url }

    func start() { connect(); RunLoop.main.run() }
    func connect() { attempt += 1; let config = URLSessionConfiguration.default; let session = URLSession(configuration: config, delegate: self, delegateQueue: nil); var req = URLRequest(url: url); req.setValue("text/event-stream", forHTTPHeaderField: "Accept"); task = session.dataTask(with: req); task?.resume(); log("connecting to \(url.absoluteString) [attempt \(attempt)]") }
    func scheduleReconnect() {
        let delay = min(pow(2.0, Double(attempt)), maxBackoff)
        log("reconnecting in \(Int(delay))s")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.connect()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { received.append(data); guard let text = String(data: data, encoding: .utf8) else { return }; for line in text.split(separator: "\n", omittingEmptySubsequences: false) { if line.hasPrefix(":") { log("comment \(line)"); continue }; if line.hasPrefix("event:") { log(String(line)) }; if line.hasPrefix("data:") { print(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) } } }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { if let error { log("connection closed: \(error.localizedDescription)") } else { log("connection closed") }; scheduleReconnect() }
    fileprivate func log(_ msg: String) {
        if let data = "[sse] \(msg)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

// Enhanced client with filters, field selection, formats, timeouts, retries
enum OutputFormat: String { case text, json, raw }
@MainActor
class FilteringSSEClient: SSEClient {
    let filters: Set<String>
    let pretty: Bool
    let format: OutputFormat
    let timeout: TimeInterval
    let maxRetries: Int?
    var fieldPath: String?

    init(url: URL, filters: [String], pretty: Bool, format: OutputFormat, timeout: TimeInterval, maxRetries: Int?, fieldPath: String?) {
        self.filters = Set(filters)
        self.pretty = pretty
        self.format = format
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.fieldPath = fieldPath
        super.init(url: url)
    }

    override func connect() {
        if let max = maxRetries, attempt >= max { log("max retries reached (\(max)); exiting"); exit(1) }
        attempt += 1
        let config = URLSessionConfiguration.default
        if timeout > 0 { config.timeoutIntervalForRequest = timeout }
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: req)
        task?.resume()
        log("connecting to \(url.absoluteString) [attempt \(attempt)]")
    }

    override func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        var currentEvent: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !filters.isEmpty, let ev = currentEvent, !filters.contains(ev) { currentEvent = nil }
                if format == .raw { print(line) }
            } else if line.hasPrefix(":") {
                if format == .raw { print(line) } else { log(line) }
            } else if line.hasPrefix("data:") {
                guard currentEvent != nil else { continue }
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if format == .raw { print(line); continue }
                if let d = payload.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) {
                    var out: Any = obj
                    if let path = fieldPath { out = extract(obj, path: path) ?? obj }
                    if format == .json, let pd = try? JSONSerialization.data(withJSONObject: out) { print(String(data: pd, encoding: .utf8) ?? payload) }
                    else if pretty, let pd = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]) { print(String(data: pd, encoding: .utf8) ?? payload) }
                    else if let pd = try? JSONSerialization.data(withJSONObject: out) { print(String(data: pd, encoding: .utf8) ?? payload) }
                    else { print(payload) }
                } else { print(payload) }
            }
        }
    }

    // Simple JSONPath-like extractor: supports $.a.b[0], wildcard [*], and array filter {key=value}
    private func extract(_ obj: Any, path: String) -> Any? {
        var norm = path
        if norm.hasPrefix("$.") { norm.removeFirst(2) }
        norm = norm.replacingOccurrences(of: "]", with: "")
        norm = norm.replacingOccurrences(of: "[", with: ".")
        var current: Any? = obj
        for part in norm.split(separator: ".").map(String.init) {
            if part == "*" {
                if let arr = current as? [Any] { current = arr.compactMap{ $0 } }
                else if let dict = current as? [String: Any] { current = Array(dict.values) }
                else { return nil }
                continue
            }
            if part.contains("{") && part.hasSuffix("}") {
                let tmp = part.replacingOccurrences(of: "}", with: "")
                let comps = tmp.split(separator: "{", maxSplits: 1).map(String.init)
                if comps.count == 2, let arr = current as? [Any] {
                    let kv = comps[1].split(separator: "=", maxSplits: 1).map(String.init)
                    if kv.count == 2 {
                        current = arr.compactMap { $0 as? [String: Any] }.filter { ($0[kv[0]] as? String) == kv[1] }
                        continue
                    }
                }
            }
            if let dict = current as? [String: Any] { current = dict[part] }
            else if let arr = current as? [Any], let idx = Int(part), idx >= 0, idx < arr.count { current = arr[idx] }
            else { return nil }
        }
        return current
    }
}

// Entry
let usage = "Usage: sse-client [--event name]* [--pretty] [--field path] [--format text|json|raw] [--timeout secs] [--max-retries n] <url>\n"
let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
    if let data = usage.data(using: .utf8) { FileHandle.standardOutput.write(data) }
    exit(0)
}
if args.contains("--version") {
    if let data = "sse-client 0.0.0\n".data(using: .utf8) { FileHandle.standardOutput.write(data) }
    exit(0)
}
var filters: [String] = []
var pretty = false
var fieldPath: String? = nil
var format: OutputFormat = .text
var timeout: TimeInterval = 0
var maxRetries: Int? = nil
var urlString: String? = nil
var i = 0
while i < args.count {
    let a = args[i]
    if a == "--event", i+1 < args.count { filters.append(args[i+1]); i += 2; continue }
    if a == "--pretty" { pretty = true; i += 1; continue }
    if a == "--field", i+1 < args.count { fieldPath = args[i+1]; i += 2; continue }
    if a == "--format", i+1 < args.count, let f = OutputFormat(rawValue: args[i+1]) { format = f; i += 2; continue }
    if a == "--timeout", i+1 < args.count, let t = TimeInterval(args[i+1]) { timeout = t; i += 2; continue }
    if a == "--max-retries", i+1 < args.count, let m = Int(args[i+1]) { maxRetries = m; i += 2; continue }
    if a.hasPrefix("-") { if let data = usage.data(using: .utf8) { FileHandle.standardError.write(data) }; exit(2) }
    urlString = a; i += 1
}
guard let raw = urlString, let url = URL(string: raw) else {
    if let data = usage.data(using: .utf8) { FileHandle.standardError.write(data) }
    exit(2)
}
FilteringSSEClient(url: url, filters: filters, pretty: pretty, format: format, timeout: timeout, maxRetries: maxRetries, fieldPath: fieldPath).start()
