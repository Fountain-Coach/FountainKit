import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CDPBrowserEngine: BrowserEngine {
    let wsURL: URL
    public init(wsURL: URL) { self.wsURL = wsURL }

    public func snapshotHTML(for url: String) async throws -> (html: String, text: String) {
        if #available(macOS 14.0, *) {
            let session = CDPSession(wsURL: wsURL)
            try await session.open()
            defer { Task { await session.close() } }
            let targetId = try await session.createTarget(url: "about:blank")
            try await session.attach(targetId: targetId)
            try await session.enablePage()
            try await session.navigate(url: url)
            try await session.waitForLoadEvent(timeoutMs: 5000)
            let html = try await session.getOuterHTML()
            let text = html.removingHTMLTags()
            return (html, text)
        } else {
            throw BrowserError.fetchFailed
        }
    }

    public func snapshot(for url: String, wait: APIModels.WaitPolicy?, capture: CaptureOptions?) async throws -> SnapshotResult {
        if #available(macOS 14.0, *) {
            let session = CDPSession(wsURL: wsURL)
            try await session.open()
            defer { Task { await session.close() } }
            let targetId = try await session.createTarget(url: "about:blank")
            try await session.attach(targetId: targetId)
            try await session.enablePage()
            try await session.enableNetwork()
            let start = Date()
            try await session.navigate(url: url)
            let strat = wait?.strategy?.lowercased()
            if strat == "domcontentloaded" {
                try await session.waitForDomContentLoaded(timeoutMs: wait?.maxWaitMs ?? 5000)
            } else if strat == "networkidle" {
                try await session.waitForLoadEvent(timeoutMs: wait?.maxWaitMs ?? 5000)
                if let idle = wait?.networkIdleMs, idle > 0 {
                    try await session.waitForNetworkIdle(idleMs: idle, timeoutMs: wait?.maxWaitMs ?? (idle + 3000))
                }
            } else {
                try await session.waitForLoadEvent(timeoutMs: wait?.maxWaitMs ?? 5000)
            }
            // Generic consent clicker (best-effort): look for common accept/agree labels and click once
            try? await session.evaluate(expression: "(function(){const texts=/(accept|agree|ok|zustimmen|einverstanden|alle.*akzept|ja)/i;const sels=['button','[role\\u003d\"button\"]','input[type\\u003dbutton]'];for(const s of sels){const btns=document.querySelectorAll(s);for(const b of btns){const label=(b.innerText||b.value||b.ariaLabel||'').toLowerCase();if(texts.test(label)){try{b.click();return true;}catch(e){}}}}return false;})()")
            // Small wait for overlays to dismiss
            try? await Task.sleep(nanoseconds: 400_000_000)
            // Gentle scroll to trigger lazy loading
            try? await session.evaluate(expression: "(function(){let y=0;const step=window.innerHeight;for(let i=0;i<5;i++){y+=step;window.scrollTo(0,y);}return true;})()")
            let loadMs = Int(Date().timeIntervalSince(start) * 1000.0)
            let html = try await session.getOuterHTML()
            let text = html.removingHTMLTags()
            let final = (try? await session.getCurrentURL()) ?? url
            // Capture selected response bodies (textual types) with truncation
            let env = ProcessInfo.processInfo.environment
            var allowed: Set<String> = [
                "text/html", "text/plain", "text/css",
                "application/json", "application/javascript", "text/javascript"
            ]
            if let raw = env["SB_NET_BODY_MIME_ALLOW"], !raw.isEmpty {
                for m in raw.split(separator: ",") { allowed.insert(String(m).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            }
            if let reqAllowed = capture?.allowedMIMEs { allowed.formUnion(reqAllowed.map { $0.lowercased() }) }
            let maxBodies = max(capture?.maxBodies ?? (Int(env["SB_NET_BODY_MAX_COUNT"] ?? "20") ?? 20), 0)
            let maxBytes = max(capture?.maxBodyBytes ?? (Int(env["SB_NET_BODY_MAX_BYTES"] ?? "16384") ?? 16384), 512)
            let maxTotal = max(capture?.maxTotalBytes ?? (Int(env["SB_NET_BODY_TOTAL_MAX_BYTES"] ?? "131072") ?? 131072), maxBytes)
            var captured: [String: String] = [:]
            var count = 0
            var total = 0
            let reqs = await session.reqs
            for (rid, info) in reqs {
                if count >= maxBodies || total >= maxTotal { break }
                if let mt = info.mimeType?.lowercased(), (info.status ?? 0) < 400 {
                    if allowed.contains(mt) || mt.hasPrefix("text/") || mt.hasSuffix("+json") {
                        if let cl = info.contentLength, cl > maxBytes { continue }
                        if let el = info.encodedLength, el > maxBytes { continue }
                        if let (body, b64) = try? await session.getResponseBody(requestId: rid) {
                            var data: Data? = nil
                            if b64 { data = Data(base64Encoded: body) } else { data = body.data(using: .utf8) }
                            if let d = data {
                                let truncated = d.prefix(maxBytes)
                                if let s = String(data: truncated, encoding: .utf8) {
                                    captured[rid] = s
                                    count += 1
                                    total += truncated.count
                                }
                            }
                        }
                    }
                }
            }
            let requests: [APIModels.Snapshot.Network.Request] = reqs.map { (rid, info) in
                APIModels.Snapshot.Network.Request(url: info.url, type: info.type, status: info.status, body: captured[rid])
            }
            let adminRequests: [AdminNetworkRequest] = reqs.map { (_, info) in
                AdminNetworkRequest(url: info.url, type: info.type, status: info.status, method: info.method, requestHeaders: info.requestHeaders, responseHeaders: info.responseHeaders)
            }
            // Main document info
            var docStatus: Int? = nil
            var docCT: String? = nil
            if let main = reqs.values.first(where: { ($0.type ?? "").lowercased() == "document" && ($0.url == final || $0.url == url) }) ?? reqs.values.first(where: { ($0.type ?? "").lowercased() == "document" }) {
                docStatus = main.status
                docCT = main.mimeType
            }
            // Best-effort screenshot capture + layout metrics
            var shot: Data? = nil
            var w: Int? = nil
            var h: Int? = nil
            var scale: Float? = 1.0
            do {
                struct Metrics: Decodable { struct Size: Decodable { let width: Double; let height: Double }; let contentSize: Size }
                let met: Metrics = try await session.sendRecv("Page.getLayoutMetrics", params: [:], result: Metrics.self)
                w = Int(met.contentSize.width)
                h = Int(met.contentSize.height)
                struct Shot: Decodable { let data: String }
                let s: Shot = try await session.sendRecv(
                    "Page.captureScreenshot",
                    params: [
                        "format": "png",
                        "captureBeyondViewport": true,
                        "fromSurface": true
                    ],
                    result: Shot.self
                )
                shot = Data(base64Encoded: s.data)
            } catch { /* ignore */ }
            // Extract client rects for headings/paragraphs and normalize to page content size
            var blockRects: [String: [NormalizedRect]]? = nil
            do {
                struct RawRect: Decodable { let x: Double; let y: Double; let w: Double; let h: Double; let excerpt: String? }
                typealias RawMap = [String: [RawRect]]
                let js = """
                (function(){
                  try {
                    const out = {};
                    let hCount = 0, pCount = 0;
                    const nodes = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6,p'));
                    for (const el of nodes) {
                      let id = (/^H[1-6]$/.test(el.tagName) ? ('h' + (hCount++)) : ('p' + (pCount++)));
                      const range = document.createRange();
                      range.selectNodeContents(el);
                      const rectList = range.getClientRects();
                      const text = (el.innerText || '').trim();
                      const rects = [];
                      for (let i=0;i<rectList.length;i++){
                        const r = rectList[i];
                        const x = r.left + window.scrollX;
                        const y = r.top + window.scrollY;
                        const w = r.width;
                        const h = r.height;
                        if (w > 0 && h > 0) rects.push({x, y, w, h, excerpt: text.slice(0,120)});
                      }
                      if (rects.length === 0) {
                        const b = el.getBoundingClientRect();
                        const x = b.left + window.scrollX;
                        const y = b.top + window.scrollY;
                        const w = b.width;
                        const h = b.height;
                        if (w > 0 && h > 0) rects.push({x, y, w, h, excerpt: text.slice(0,120)});
                      }
                      out[id] = rects;
                    }
                    return out;
                  } catch (e) { return {}; }
                })()
                """
                if let raw: RawMap = try await session.evalValue(expression: js, as: RawMap.self), let wpx = w, let hpx = h, wpx > 0, hpx > 0 {
                    var norm: [String: [NormalizedRect]] = [:]
                    for (k, arr) in raw {
                        var list: [NormalizedRect] = []
                        for r in arr {
                            let nx = max(0.0, min(1.0, Float(r.x / Double(wpx))))
                            let ny = max(0.0, min(1.0, Float(r.y / Double(hpx))))
                            let nw = max(0.0, min(1.0, Float(r.w / Double(wpx))))
                            let nh = max(0.0, min(1.0, Float(r.h / Double(hpx))))
                            list.append(NormalizedRect(x: nx, y: ny, w: nw, h: nh, excerpt: r.excerpt, confidence: 0.9))
                        }
                        if !list.isEmpty { norm[k] = list }
                    }
                    if !norm.isEmpty { blockRects = norm }
                }
            } catch { /* ignore rects */ }
            return SnapshotResult(
                html: html,
                text: text,
                finalURL: final,
                loadMs: loadMs,
                network: requests,
                pageStatus: docStatus,
                pageContentType: docCT,
                adminNetwork: adminRequests,
                screenshotPNG: shot,
                screenshotWidth: w,
                screenshotHeight: h,
                screenshotScale: scale,
                blockRects: blockRects
            )
        } else {
            throw BrowserError.fetchFailed
        }
    }
}

@available(macOS 14.0, *)
private struct CDPRuntimeEnableAck: Decodable {}
@available(macOS 14.0, *)
private struct CDPEvalResult<T: Decodable>: Decodable { struct Inner: Decodable { let value: T? }; let result: Inner }
@available(macOS 14.0, *)
actor CDPSession {
    let wsURL: URL
    var task: URLSessionWebSocketTask?
    var nextId: Int = 1
    // Network tracking
    var inflight: Set<String> = []
    struct ReqInfo { var url: String; var type: String?; var status: Int?; var mimeType: String?; var body: String?; var encodedLength: Int?; var contentLength: Int?; var method: String?; var requestHeaders: [String: String]?; var responseHeaders: [String: String]? }
    var reqs: [String: ReqInfo] = [:]
    init(wsURL: URL) { self.wsURL = wsURL }
    func open() async throws {
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: wsURL)
        self.task = task
        task.resume()
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    func close() {
        task?.cancel()
    }
    private func processEventObject(_ obj: [String: Any]) {
        guard let method = obj["method"] as? String, let params = obj["params"] as? [String: Any] else { return }
        switch method {
        case "Network.requestWillBeSent":
            if let rid = params["requestId"] as? String, let req = params["request"] as? [String: Any], let url = req["url"] as? String {
                inflight.insert(rid)
                var info = reqs[rid] ?? ReqInfo(url: url, type: nil, status: nil, mimeType: nil, body: nil, encodedLength: nil, contentLength: nil, method: nil, requestHeaders: nil, responseHeaders: nil)
                if let t = params["type"] as? String { info.type = t }
                if let m = req["method"] as? String { info.method = m }
                if let hdrs = req["headers"] as? [String: Any] { var h: [String:String] = [:]; for (k,v) in hdrs { h[k] = "\(v)" }; info.requestHeaders = h }
                reqs[rid] = info
            }
        case "Network.responseReceived":
            if let rid = params["requestId"] as? String, let resp = params["response"] as? [String: Any] {
                var info = reqs[rid] ?? ReqInfo(url: "", type: nil, status: nil, mimeType: nil, body: nil, encodedLength: nil, contentLength: nil, method: nil, requestHeaders: nil, responseHeaders: nil)
                if let s = resp["status"] as? Int { info.status = s }
                if let t = params["type"] as? String { info.type = t }
                if let url = resp["url"] as? String, info.url.isEmpty { info.url = url }
                if let mt = resp["mimeType"] as? String { info.mimeType = mt }
                if let hdrs = resp["headers"] as? [String: Any] { var h: [String:String] = [:]; for (k,v) in hdrs { h[k] = "\(v)"; if k.lowercased()=="content-length" { if let s=v as? String, let n=Int(s){ info.contentLength=n } else if let n=v as? Int { info.contentLength=n } else if let n=v as? Double { info.contentLength=Int(n) } } }; info.responseHeaders = h }
                reqs[rid] = info
            }
        case "Network.loadingFinished":
            if let rid = params["requestId"] as? String {
                inflight.remove(rid)
                if let len = params["encodedDataLength"] as? Double {
                    var info = reqs[rid] ?? ReqInfo(url: "", type: nil, status: nil, mimeType: nil, body: nil, encodedLength: nil, contentLength: nil, method: nil, requestHeaders: nil, responseHeaders: nil)
                    info.encodedLength = Int(len)
                    reqs[rid] = info
                }
            }
        case "Network.loadingFailed":
            if let rid = params["requestId"] as? String { inflight.remove(rid) }
        default:
            break
        }
    }

    func sendRecv<T: Decodable>(_ method: String, params: [String: Any]? = nil, result: T.Type) async throws -> T {
        guard let task else { throw BrowserError.fetchFailed }
        let id = nextId; nextId += 1
        var obj: [String: Any] = ["id": id, "method": method]
        if let params { obj["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: obj)
        try await task.send(.data(data))
        while true {
            let msg = try await task.receive()
            switch msg {
            case .data(let d):
                let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
                if let m = j, m["method"] != nil { processEventObject(m) }
                if let rid = j?["id"] as? Int, rid == id {
                    if let res = j?["result"] {
                        let rd = try JSONSerialization.data(withJSONObject: res)
                        return try JSONDecoder().decode(T.self, from: rd)
                    } else { throw BrowserError.fetchFailed }
                }
            case .string(let s):
                if let d = s.data(using: .utf8) {
                    let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
                    if let m = j, m["method"] != nil { processEventObject(m) }
                    if let rid = j?["id"] as? Int, rid == id {
                        if let res = j?["result"] {
                            let rd = try JSONSerialization.data(withJSONObject: res)
                            return try JSONDecoder().decode(T.self, from: rd)
                        } else { throw BrowserError.fetchFailed }
                    }
                }
            @unknown default: break
            }
        }
    }
    func createTarget(url: String) async throws -> String {
        struct R: Decodable { let targetId: String }
        let r: R = try await sendRecv("Target.createTarget", params: ["url": url], result: R.self)
        return r.targetId
    }
    func attach(targetId: String) async throws {
        struct R: Decodable { let sessionId: String }
        _ = try await sendRecv("Target.attachToTarget", params: ["targetId": targetId, "flatten": true], result: R.self)
    }
    func enablePage() async throws { struct R: Decodable {}; _ = try await sendRecv("Page.enable", params: [:], result: R.self) }
    func enableNetwork() async throws { struct R: Decodable {}; _ = try await sendRecv("Network.enable", params: [:], result: R.self) }
    func navigate(url: String) async throws { struct R: Decodable {}; _ = try await sendRecv("Page.navigate", params: ["url": url], result: R.self) }
    func waitForLoadEvent(timeoutMs: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs)/1000.0)
        while Date() < deadline {
            guard let task else { throw BrowserError.fetchFailed }
            do {
                let msg = try await withTaskCancellationHandler(operation: {
                    try await withTimeout(seconds: 0.5) { try await task.receive() }
                }, onCancel: { })
                switch msg {
                case .data(let d):
                    if let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        if (m["method"] as? String) == "Page.loadEventFired" { return }
                        processEventObject(m)
                    }
                case .string(let s):
                    if let d = s.data(using: .utf8), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        if (m["method"] as? String) == "Page.loadEventFired" { return }
                        processEventObject(m)
                    }
                @unknown default: break
                }
            } catch { /* ignore timeouts */ }
        }
    }
    func waitForDomContentLoaded(timeoutMs: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs)/1000.0)
        while Date() < deadline {
            guard let task else { throw BrowserError.fetchFailed }
            do {
                let msg = try await withTaskCancellationHandler(operation: {
                    try await withTimeout(seconds: 0.5) { try await task.receive() }
                }, onCancel: { })
                switch msg {
                case .data(let d):
                    if let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        if (m["method"] as? String) == "Page.domContentEventFired" { return }
                        processEventObject(m)
                    }
                case .string(let s):
                    if let d = s.data(using: .utf8), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        if (m["method"] as? String) == "Page.domContentEventFired" { return }
                        processEventObject(m)
                    }
                @unknown default: break
                }
            } catch { /* ignore timeouts */ }
        }
    }
    func waitForNetworkIdle(idleMs: Int, timeoutMs: Int) async throws {
        let overallDeadline = Date().addingTimeInterval(Double(timeoutMs)/1000.0)
        var idleStart: Date? = nil
        while Date() < overallDeadline {
            if inflight.isEmpty {
                if idleStart == nil { idleStart = Date() }
                if let started = idleStart, Int(Date().timeIntervalSince(started) * 1000.0) >= idleMs { return }
            } else {
                idleStart = nil
            }
            // drain events for a short period
            guard let task else { throw BrowserError.fetchFailed }
            do {
                let msg = try await withTimeout(seconds: 0.2) { try await task.receive() }
                switch msg {
                case .data(let d):
                    if let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { processEventObject(m) }
                case .string(let s):
                    if let d = s.data(using: .utf8), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { processEventObject(m) }
                @unknown default: break
                }
            } catch { /* time slice idle */ }
        }
    }
    func getOuterHTML() async throws -> String {
        struct GetDoc: Decodable { let root: Node }
        struct Node: Decodable { let nodeId: Int }
        let doc: GetDoc = try await sendRecv("DOM.getDocument", params: ["depth": -1], result: GetDoc.self)
        struct Outer: Decodable { let outerHTML: String }
        let out: Outer = try await sendRecv("DOM.getOuterHTML", params: ["nodeId": doc.root.nodeId], result: Outer.self)
        return out.outerHTML
    }
    func evaluate(expression: String) async throws {
        _ = try await sendRecv("Runtime.enable", params: [:], result: CDPRuntimeEnableAck.self)
        struct EvalVoid: Decodable {}
        _ = try await sendRecv("Runtime.evaluate", params: ["expression": expression, "returnByValue": true], result: EvalVoid.self)
    }
    func evalValue<T: Decodable>(expression: String, as: T.Type) async throws -> T? {
        _ = try await sendRecv("Runtime.enable", params: [:], result: CDPRuntimeEnableAck.self)
        let r: CDPEvalResult<T> = try await sendRecv("Runtime.evaluate", params: ["expression": expression, "returnByValue": true], result: CDPEvalResult<T>.self)
        return r.result.value
    }
    func getResponseBody(requestId: String) async throws -> (String, Bool) {
        struct BodyRes: Decodable { let body: String; let base64Encoded: Bool }
        let r: BodyRes = try await sendRecv("Network.getResponseBody", params: ["requestId": requestId], result: BodyRes.self)
        return (r.body, r.base64Encoded)
    }
    func getCurrentURL() async throws -> String? {
        struct Hist: Decodable { let currentIndex: Int; let entries: [Entry] }
        struct Entry: Decodable { let url: String }
        let h: Hist = try await sendRecv("Page.getNavigationHistory", params: [:], result: Hist.self)
        if h.currentIndex >= 0 && h.currentIndex < h.entries.count { return h.entries[h.currentIndex].url }
        return nil
    }
}

@available(macOS 14.0, *)
func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); throw BrowserError.fetchFailed }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
