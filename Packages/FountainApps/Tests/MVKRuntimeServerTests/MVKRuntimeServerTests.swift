import XCTest
import Foundation
import MIDI2
import MetalViewKitRuntimeServerKit
@testable import midi_instrument_host
import MetalViewKit
import FountainRuntime

final class MVKRuntimeServerTests: XCTestCase {
    struct RunningServer {
        let port: Int
        let server: NIOHTTPServer
    }

    override func setUp() async throws {
        // Ensure loopback hub is clean between tests
        LoopbackMetalInstrumentTransport.shared.reset()
    }

    // Boot the runtime server on an ephemeral port
    private static func startServer() async throws -> RunningServer {
        // Serve spec at /openapi.yaml as fallback
        let fallback = HTTPKernel { req in
            if req.path == "/openapi.yaml" {
                let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/metalviewkit-runtime-server/openapi.yaml")
                if let data = try? Data(contentsOf: url) {
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
                }
            } else if req.path == "/v1/midi/events" {
                let empty = try? JSONSerialization.data(withJSONObject: ["events": []])
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: empty ?? Data())
            }
            return HTTPResponse(status: 404)
        }
        let transport = NIOOpenAPIServerTransport(fallback: fallback)
        try MetalViewKitRuntimeServer.register(on: transport)
        let server = NIOHTTPServer(kernel: transport.asKernel())
        let bound = try await server.start(port: 0)
        return .init(port: bound, server: server)
    }

    private func url(_ port: Int, _ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    @MainActor
    private func loadFactsData(agentId: String, corpus: String) async -> Data? {
        guard let facts = await MIDIInstrumentHost.loadFacts(agentId: agentId, corpus: corpus) else { return nil }
        return try? JSONSerialization.data(withJSONObject: facts)
    }
}

actor WordCollector {
    private var items: [[UInt32]] = []
    func append(_ words: [UInt32]) { items.append(words) }
    func snapshot() -> [[UInt32]] { items }
}

extension MVKRuntimeServerTests {
    func testHealth() async throws {
        let running = try await Self.startServer()
        defer { Task { try? await running.server.stop() } }
        let (data, resp) = try await URLSession.shared.data(from: url(running.port, "/health"))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["status"] as? String, "ok")
        XCTAssertNotNil(obj["uptimeSec"])
    }

    func testMidiEventsForwardingByDisplayName() async throws {
        let running = try await Self.startServer()
        defer { Task { try? await running.server.stop() } }

        // Create a loopback instrument session that will receive UMP
        let descriptor = MetalInstrumentDescriptor(
            manufacturer: "Fountain",
            product: "Canvas",
            instanceId: UUID().uuidString,
            displayName: "QuietFrame Canvas",
            midiGroup: 0
        )
        let collector = WordCollector()
        let session = try LoopbackMetalInstrumentTransport.shared.makeSession(descriptor: descriptor) { words in
            Task { await collector.append(words) }
        }
        defer { session.close() }

        // Build a simple NoteOn UMP (two words)
        let w0: UInt32 = (0x4 << 28) | (0 << 24) | (0x9 << 20) | (0 << 16) | (60 << 8)
        let w1: UInt32 = UInt32((Double(100) * 65535.0 / 127.0).rounded()) << 16
        let body: [String: Any] = [
            "events": [[
                "tNs": "0",
                "packet": ["w0": Int(w0), "w1": Int(w1)]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: url(running.port, "/v1/midi/events?targetDisplayName=QuietFrame"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, postResp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((postResp as? HTTPURLResponse)?.statusCode, 202)

        // Allow loopback dispatch
        try await Task.sleep(nanoseconds: 50_000_000)
        let received = await collector.snapshot()
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first!, [w0, w1])
    }

    func testMidiEventsForwardingByInstanceId() async throws {
        let running = try await Self.startServer()
        defer { Task { try? await running.server.stop() } }

        let iid = UUID().uuidString
        let descriptor = MetalInstrumentDescriptor(
            manufacturer: "Fountain",
            product: "Canvas",
            instanceId: iid,
            displayName: "Canvas#\(iid)",
            midiGroup: 0
        )
        let collector = WordCollector()
        let session = try LoopbackMetalInstrumentTransport.shared.makeSession(descriptor: descriptor) { words in
            Task { await collector.append(words) }
        }
        defer { session.close() }

        let w0: UInt32 = (0x4 << 28) | (0 << 24) | (0xB << 20) | (0 << 16) | (1 << 8)
        let w1: UInt32 = 0x7F // CC value (packed by sender)
        let body: [String: Any] = [
            "events": [[
                "tNs": "0",
                "packet": ["w0": Int(w0), "w1": Int(w1)]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: url(running.port, "/v1/midi/events?targetInstanceId=\(iid)"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, postResp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((postResp as? HTTPURLResponse)?.statusCode, 202)

        try await Task.sleep(nanoseconds: 50_000_000)
        let received = await collector.snapshot()
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first!, [w0, w1])
    }

    func testEndpointsCRUD() async throws {
        let running = try await Self.startServer()
        defer { Task { try? await running.server.stop() } }

        // Initially empty
        do {
            let (data, resp) = try await URLSession.shared.data(from: url(running.port, "/v1/midi/endpoints"))
            XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
            let arr = try JSONSerialization.jsonObject(with: data) as! [Any]
            XCTAssertEqual(arr.count, 0)
        }

        // Create one
        let create: [String: Any] = ["name": "test-ep", "direction": "input", "groups": 1, "jrTimestampSupport": true]
        var req = URLRequest(url: url(running.port, "/v1/midi/endpoints"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: create)
        let (cdata, cresp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((cresp as? HTTPURLResponse)?.statusCode, 201)
        let obj = try JSONSerialization.jsonObject(with: cdata) as! [String: Any]
        // Shape is allOf(MidiEndpointCreate, {id}) flattened by generator; verify keys exist
        XCTAssertNotNil(obj["name"])
        XCTAssertNotNil(obj["direction"])
        XCTAssertNotNil(obj["id"])

        // Now list returns 1
        do {
            let (data, resp) = try await URLSession.shared.data(from: url(running.port, "/v1/midi/endpoints"))
            XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
            let arr = try JSONSerialization.jsonObject(with: data) as! [Any]
            XCTAssertEqual(arr.count, 1)
        }
    }

    func testReadMidiEventsStub() async throws {
        let running = try await Self.startServer()
        defer { Task { try? await running.server.stop() } }
        let (data, resp) = try await URLSession.shared.data(from: url(running.port, "/v1/midi/events"))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(obj["events"]) // currently empty array
    }

    func testLiveLoopbackListing() async throws {
        let running = try await Self.startServer()
        defer { Task { try? await running.server.stop() } }

        // Create a loopback instrument session
        let iid = UUID().uuidString
        let desc = MetalInstrumentDescriptor(manufacturer: "Fountain", product: "Test", instanceId: iid, displayName: "Test#\(iid)")
        let session = try LoopbackMetalInstrumentTransport.shared.makeSession(descriptor: desc) { _ in }
        defer { session.close() }

        // List endpoints and ensure our live session is present
        let (data, resp) = try await URLSession.shared.data(from: url(running.port, "/v1/midi/endpoints"))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let arr = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let hasLive = arr.contains { ep in
            (ep["id"] as? String) == iid || (ep["value2"] as? [String: Any])?["id"] as? String == iid
        }
        XCTAssertTrue(hasLive, "expected live loopback endpoint with id \(iid)")
    }

    /// End-to-end bridge: MIDI Instrument Host PE -> HTTP -> runtime instrument state (using the FountainGUIKit demo agent id).
    @MainActor
    func testInstrumentStateViaMidiHostPropertyExchange() async throws {
        let running = try await Self.startServer()
        defer { Task { try? await running.server.stop() } }

        // Load facts for the FountainGUIKit demo agent (seeded via openapi-to-facts from both
        // fountain-gui-demo.yml and metalviewkit-runtime.yml).
        let agentId = "fountain.coach/agent/fountain-gui-demo/service"
        let corpus = "agents"
        guard
            let factsData = await loadFactsData(agentId: agentId, corpus: corpus),
            let facts = try? JSONSerialization.jsonObject(with: factsData) as? [String: Any]
        else {
            XCTFail("missing facts for \(agentId)")
            return
        }

        // Build property routes with a base URL pointing at this runtime instance.
        let safe = agentId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .uppercased()
        let envKey = "AGENT_BASE_URL_\(safe)"
        let baseURL = "http://127.0.0.1:\(running.port)"
        let env = [envKey: baseURL]
        let routes = MIDIInstrumentHost.buildPropertyRoutes(agentId: agentId, facts: facts, env: env)

        // Find the POST route that maps to /v1/instruments/{id}/state.
        var propName: String?
        for (name, route) in routes where route.method == "POST" && route.path == "/v1/instruments/{id}/state" {
            propName = name
            break
        }
        guard let propName else { XCTFail("no runtime instrument state route found in property routes"); return }

        // Compose a PE SET body targeting the generic instrument state operation.
        let instrumentId = "demo-pe"
        let bodyObject: [String: Any] = [
            "properties": [
                [
                    "name": propName,
                    "value": [
                        // Path parameter substitution for {id}
                        "id": instrumentId,
                        // JSON request body for InstrumentState
                        "body": [
                            "properties": [
                                "canvas.zoom": 1.25,
                                "canvas.translation.x": 7.0,
                                "canvas.translation.y": -3.5
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: bodyObject)
        let pe = MidiCiPropertyExchangeBody(
            command: .set,
            requestId: 1,
            encoding: .json,
            header: [:],
            data: Array(payload)
        )

        // Invoke the host's PE handler; we don't care about outbound notify traffic here.
        await MIDIInstrumentHost.handlePE(pe, propertyMap: routes, group: 0, tx: [])

        // Verify runtime state was updated via HTTP.
        let stateURL = url(running.port, "/v1/instruments/\(instrumentId)/state")
        let (sdata, sresp) = try await URLSession.shared.data(from: stateURL)
        XCTAssertEqual((sresp as? HTTPURLResponse)?.statusCode, 200)
        let sobj = try JSONSerialization.jsonObject(with: sdata) as! [String: Any]
        guard let props = sobj["properties"] as? [String: Any] else {
            XCTFail("missing properties in InstrumentState")
            return
        }
        XCTAssertEqual(props["canvas.zoom"] as? Double, 1.25)
        XCTAssertEqual(props["canvas.translation.x"] as? Double, 7.0)
        XCTAssertEqual(props["canvas.translation.y"] as? Double, -3.5)
    }
}
