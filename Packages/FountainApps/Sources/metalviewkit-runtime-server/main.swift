import Foundation
import OpenAPIRuntime
import FountainRuntime
import MetalViewKitRuntimeServerKit
// CI decode can be added via SafeMidiCI in QuietFrameKit; for fallback routes we do a guarded light parse to avoid linking issues.

let env = ProcessInfo.processInfo.environment
let port = Int(env["MVK_RUNTIME_PORT"] ?? env["PORT"] ?? "7777") ?? 7777

final class MVKRuntimeEventStore: @unchecked Sendable {
    var ciEvents: [[String: Any]] = []
    var noteEvents: [[String: Any]] = []
}

fileprivate let _eventStore = MVKRuntimeEventStore()

let fallback = HTTPKernel { req in
    // Serve curated spec via local $ref file
    if req.path == "/openapi.yaml" {
        let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/MetalViewKitRuntimeServerKit/openapi.yaml")
        if let data = try? Data(contentsOf: url) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
        }
        return HTTPResponse(status: 404)
    }

    // SSE: tracing events
    if req.path.split(separator: "?").first == "/v1/tracing/sse" {
        // Emit current trace array repeatedly as SSE frames
        let line = "data: \(MetalViewKitRuntimeServer.tracingJSON())\n\n"
        // Simulate streaming with multiple chunks
        let body = Data(Array(repeating: line, count: 10).joined().utf8)
        return HTTPResponse(status: 200,
                            headers: [
                                "Content-Type": "text/event-stream",
                                // Signal the server to chunk and flush pieces progressively
                                "X-Chunked-SSE": "1"
                            ],
                            body: body)
    }

    // SSE: audio backend events
    if req.path.split(separator: "?").first == "/v1/audio/backend/events-sse" {
        let line = "data: \(MetalViewKitRuntimeServer.backendEventJSON())\n\n"
        let body = Data(Array(repeating: line, count: 20).joined().utf8)
        return HTTPResponse(status: 200,
                            headers: [
                                "Content-Type": "text/event-stream",
                                "X-Chunked-SSE": "1"
                            ],
                            body: body)
    }

    // CI parser: POST /v1/midi/ci/parse, body { "sysEx7": [ints] }
    if req.path.split(separator: "?").first == "/v1/midi/ci/parse" {
        let body = req.body
        guard let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let arr = obj["sysEx7"] as? [Any] else {
            return HTTPResponse(status: 400)
        }
        let bytes: [UInt8] = arr.compactMap { v in
            if let i = v as? Int { return UInt8(truncatingIfNeeded: i) }
            if let s = v as? String, s.hasPrefix("0x"), let n = UInt8(s.dropFirst(2), radix: 16) { return n }
            return nil
        }
        if let out = ciEnvelopeJSONLight(bytes) {
            if let data = try? JSONSerialization.data(withJSONObject: out) {
                _eventStore.ciEvents.append(out)
                if _eventStore.ciEvents.count > 1000 {
                    _eventStore.ciEvents.removeFirst(_eventStore.ciEvents.count - 1000)
                }
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
            }
        }
        return HTTPResponse(status: 422)
    }
    // Note events ingest: POST /v1/midi/notes/ingest { events: [ {event:"noteOn", note, velocity, channel, group, tNs} ... ] }
    if req.path.split(separator: "?").first == "/v1/midi/notes/ingest" {
        guard let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else {
            return HTTPResponse(status: 400)
        }
        if let ev = obj["event"] as? String { // single event form
            var e = obj; e["tNs"] = e["tNs"] ?? "\(DispatchTime.now().uptimeNanoseconds)"
            _eventStore.noteEvents.append(e)
        }
        if let arr = obj["events"] as? [[String: Any]] { // batch form
            for var e0 in arr {
                if e0["tNs"] == nil { e0["tNs"] = "\(DispatchTime.now().uptimeNanoseconds)" }
                _eventStore.noteEvents.append(e0)
            }
        }
        if _eventStore.noteEvents.count > 2000 {
            _eventStore.noteEvents.removeFirst(_eventStore.noteEvents.count - 2000)
        }
        return HTTPResponse(status: 204)
    }
    // CI SSE stream
    if req.path.split(separator: "?").first == "/v1/midi/ci/sse" {
        let json = (try? JSONSerialization.data(withJSONObject: _eventStore.ciEvents))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let line = "data: \(json)\n\n"
        let body = Data(Array(repeating: line, count: 10).joined().utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/event-stream", "X-Chunked-SSE": "1"], body: body)
    }
    // Notes SSE stream
    if req.path.split(separator: "?").first == "/v1/midi/notes/stream" {
        let json = (try? JSONSerialization.data(withJSONObject: _eventStore.noteEvents))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let line = "data: \(json)\n\n"
        let body = Data(Array(repeating: line, count: 10).joined().utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/event-stream", "X-Chunked-SSE": "1"], body: body)
    }
    return HTTPResponse(status: 404)
}

let transport = NIOOpenAPIServerTransport(fallback: fallback)
do { try MetalViewKitRuntimeServer.register(on: transport) } catch {
    FileHandle.standardError.write(Data("[mvk-runtime] register failed: \(error)\n".utf8))
}
// WebSocket routes: tracing stream and backend events
let ws: [String: @Sendable () -> String] = [
    "/v1/tracing/stream": { MetalViewKitRuntimeServer.tracingJSON() },
    "/v1/audio/backend/events": { MetalViewKitRuntimeServer.backendEventJSON() }
]
let sse: [String: @Sendable () -> String] = [
    "/v1/tracing/sse": { MetalViewKitRuntimeServer.tracingJSON() },
    "/v1/audio/backend/events-sse": { MetalViewKitRuntimeServer.backendEventJSON() },
    "/v1/midi/ci/sse": { MetalViewKitRuntimeServer.tracingJSON() },
    "/v1/midi/notes/stream": {
        (try? String(
            data: JSONSerialization.data(withJSONObject: _eventStore.noteEvents),
            encoding: .utf8
        )) ?? "[]"
    }
]
let server = NIOHTTPServer(kernel: transport.asKernel(), webSocketRoutes: ws, sseRoutes: sse)

Task {
    do {
        var bound: Int
        do { bound = try await server.start(port: port) } catch { bound = try await server.start(port: 0) }
        print("metalviewkit-runtime listening on :\(bound)")
    } catch {
        FileHandle.standardError.write(Data("[mvk-runtime] failed to start: \(error)\n".utf8))
        exit(2)
    }
}
dispatchMain()

// MARK: - CI helpers (light validator)
func ciEnvelopeJSONLight(_ bytes: [UInt8]) -> [String: Any]? {
    guard bytes.count >= 7, bytes.first == 0xF0, bytes.last == 0xF7 else { return nil }
    let manuf = bytes[1]
    guard manuf == 0x7E || manuf == 0x7F else { return nil }
    // F0 7E/7F <devId> 0x0D <subId2> ... F7
    guard bytes[3] == 0x0D else { return nil }
    let scope = (manuf == 0x7E) ? "nonRealtime" : "realtime"
    let subId2 = (bytes.count > 4) ? bytes[4] : 0
    return [
        "scope": scope,
        "subId2": Int(subId2),
        "length": bytes.count
    ]
}
