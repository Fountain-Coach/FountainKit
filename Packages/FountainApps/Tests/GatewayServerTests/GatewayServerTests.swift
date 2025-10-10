import XCTest
import FountainRuntime
@testable import gateway_server

final class GatewayServerTests: XCTestCase {
    override class func setUp() {
        // Seed credentials for token issuance
        setenv("GATEWAY_CRED_test", "secret", 1)
        setenv("GATEWAY_JWT_SECRET", "topsecret", 1)
    }

    func makeAPI() -> GatewayOpenAPI {
        let server = GatewayServer()
        return GatewayOpenAPI(host: server)
    }

    func testHealth() async throws {
        let api = makeAPI()
        let out = try await api.gatewayHealth(.init(headers: .init()))
        switch out { case .ok: break; default: XCTFail("expected ok") }
    }

    func testIssueAuthToken() async throws {
        let api = makeAPI()
        let creds = Components.Schemas.CredentialRequest(clientId: "test", clientSecret: "secret")
        let out = try await api.issueAuthToken(.init(headers: .init(), body: .json(creds)))
        guard case let .ok(ok) = out, case let .json(tok) = ok.body else {
            return XCTFail("expected token response")
        }
        XCTAssertFalse(tok.token.isEmpty)
    }

    func testRoutesCRUD() async throws {
        let api = makeAPI()
        // Create
        let route = Components.Schemas.RouteInfo(
            id: "t1",
            path: "/api",
            target: "http://localhost:8000",
            methods: ["GET"],
            rateLimit: 50,
            proxyEnabled: true
        )
        let created = try await api.createRoute(.init(headers: .init(), body: .json(route)))
        guard case let .created(ok) = created, case let .json(r1) = ok.body else { return XCTFail("create failed") }
        XCTAssertEqual(r1.id, "t1")

        // List
        let list = try await api.listRoutes(.init(headers: .init()))
        guard case let .ok(ok2) = list, case let .json(routesPayload) = ok2.body else { return XCTFail("list failed") }
        XCTAssertTrue((routesPayload ?? []).contains(where: { $0.id == "t1" }))

        // Update
        let routeUpd = Components.Schemas.RouteInfo(
            id: "t1",
            path: "/api",
            target: "http://localhost:8000",
            methods: ["GET"],
            rateLimit: 100,
            proxyEnabled: true
        )
        let updated = try await api.updateRoute(.init(path: .init(routeId: "t1"), headers: .init(), body: .json(routeUpd)))
        guard case let .ok(ok3) = updated, case let .json(r3) = ok3.body else { return XCTFail("update failed") }
        XCTAssertEqual(r3.rateLimit, 100)

        // Delete
        let deleted = try await api.deleteRoute(.init(path: .init(routeId: "t1"), headers: .init()))
        guard case .noContent = deleted else { return XCTFail("delete failed") }
    }

    func testMetricsOk() async throws {
        // For OpenAPI handler direct call, metrics auth is handled at kernel level;
        // Here we verify the underlying host metrics returns 200 and is JSON.
        let server = GatewayServer()
        let resp = await server.gatewayMetrics()
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(resp.headers["Content-Type"], "application/json")
    }

    func testCertificateEndpoints() async throws {
        let api = makeAPI()
        // Renew should be accepted
        let renew = try await api.renewCertificate(.init(headers: .init()))
        guard case .accepted = renew else { return XCTFail("renew expected accepted") }
        // Info without configured certificate path should not be ok
        let info = try await api.certificateInfo(.init(headers: .init()))
        switch info { case .ok: XCTFail("unexpected ok without cert"); default: break }
    }

    func testE2EMetricsAuthHTTP() async throws {
        // Seed env for token issuance and admin role
        setenv("GATEWAY_CRED_admin", "s3cr3t", 1)
        setenv("GATEWAY_ROLE_admin", "admin", 1)
        setenv("GATEWAY_JWT_SECRET", "topsecret", 1)

        // Start on a high, likely-free port
        let port = 18099
        let running = await ServerTestUtils.startGateway(on: port)

        // 1) metrics without token -> 401
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/metrics")!)
        req.httpMethod = "GET"
        let (mdata, mresp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((mresp as? HTTPURLResponse)?.statusCode, 401, String(data: mdata, encoding: .utf8) ?? "")

        // 2) issue token
        var tReq = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/auth/token")!)
        tReq.httpMethod = "POST"
        tReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        tReq.httpBody = try JSONSerialization.data(withJSONObject: ["clientId": "admin", "clientSecret": "s3cr3t"]) 
        let (td, tr) = try await URLSession.shared.data(for: tReq)
        XCTAssertEqual((tr as? HTTPURLResponse)?.statusCode, 200, String(data: td, encoding: .utf8) ?? "")
        struct Tok: Decodable { let token: String }
        let tok = try JSONDecoder().decode(Tok.self, from: td)

        // 3) metrics with bearer -> 200
        var okReq = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/metrics")!)
        okReq.httpMethod = "GET"
        okReq.setValue("Bearer \(tok.token)", forHTTPHeaderField: "Authorization")
        let (_, okR) = try await URLSession.shared.data(for: okReq)
        XCTAssertEqual((okR as? HTTPURLResponse)?.statusCode, 200)

        // Stop server
        await running.stop()
    }

    func testE2ERoutesCRUDHTTP() async throws {
        setenv("GATEWAY_CRED_admin", "s3cr3t", 1)
        setenv("GATEWAY_ROLE_admin", "admin", 1)
        setenv("GATEWAY_JWT_SECRET", "topsecret", 1)
        let port = 18101
        let running = await ServerTestUtils.startGateway(on: port)
        defer { Task { await running.stop() } }

        // Issue token
        let tokenURL = URL(string: "http://127.0.0.1:\(port)/auth/token")!
        let (td, tr) = try await ServerTestUtils.httpJSON("POST", tokenURL, body: ["clientId": "admin", "clientSecret": "s3cr3t"]) 
        XCTAssertEqual(tr.statusCode, 200)
        struct Tok: Decodable { let token: String }
        let tok = try JSONDecoder().decode(Tok.self, from: td)
        let auth = ["Authorization": "Bearer \(tok.token)"]

        // Create route
        let routesURL = URL(string: "http://127.0.0.1:\(port)/routes")!
        let route: [String: Any] = [
            "id": "e2e",
            "path": "/e2e",
            "target": "http://localhost:9999",
            "methods": ["GET"],
            "rateLimit": 5,
            "proxyEnabled": true
        ]
        let (cd, cr) = try await ServerTestUtils.httpJSON("POST", routesURL, headers: auth, body: route)
        XCTAssertEqual(cr.statusCode, 201, String(data: cd, encoding: .utf8) ?? "")

        // List routes
        let (ld, lr) = try await ServerTestUtils.httpJSON("GET", routesURL, headers: auth)
        XCTAssertEqual(lr.statusCode, 200)
        let list = try JSONDecoder().decode([Components.Schemas.RouteInfo].self, from: ld)
        XCTAssertTrue(list.contains(where: { $0.id == "e2e" }))

        // Update route
        let routeUpd: [String: Any] = [
            "id": "e2e",
            "path": "/e2e",
            "target": "http://localhost:9999",
            "methods": ["GET"],
            "rateLimit": 10,
            "proxyEnabled": true
        ]
        let updateURL = URL(string: "http://127.0.0.1:\(port)/routes/e2e")!
        let (ud, ur) = try await ServerTestUtils.httpJSON("PUT", updateURL, headers: auth, body: routeUpd)
        XCTAssertEqual(ur.statusCode, 200, String(data: ud, encoding: .utf8) ?? "")

        // Delete route
        let (_, dr) = try await ServerTestUtils.httpJSON("DELETE", updateURL, headers: auth)
        XCTAssertEqual(dr.statusCode, 204)
    }

    func testRoutesReloadFromFile() async throws {
        // Prepare temp routes file with one route
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent("routes.json")
        let route: [String: Any] = [
            "id": "file1",
            "path": "/file",
            "target": "http://localhost:9000",
            "methods": ["GET"],
            "rateLimit": 10,
            "proxyEnabled": true
        ]
        let data = try JSONSerialization.data(withJSONObject: [route])
        try data.write(to: file)

        let server = GatewayServer(routeStoreURL: file)
        server.reloadRoutes()
        let resp = server.listRoutes()
        XCTAssertEqual(resp.status, 200)
        let list = try JSONDecoder().decode([Components.Schemas.RouteInfo].self, from: resp.body)
        XCTAssertTrue(list.contains(where: { $0.id == "file1" }))
    }

    func testZonesAndRecordsFallbackRoutes() async throws {
        // Setup ZoneManager with a temp YAML file
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let yaml = tmpDir.appendingPathComponent("zones.yaml")
        let manager = try ZoneManager(fileURL: yaml)
        let server = GatewayServer(zoneManager: manager)

        // Create zone via HTTP-like API
        let createZoneReq = FountainRuntime.HTTPRequest(method: "POST", path: "/zones", headers: ["Content-Type": "application/json"], body: try JSONEncoder().encode(["name": "example.com"]))
        let cz = await server.createZone(createZoneReq)
        XCTAssertEqual(cz.status, 201)
        struct ZoneOut: Decodable { let id: String; let name: String }
        let zone = try JSONDecoder().decode(ZoneOut.self, from: cz.body)

        // Create record
        let recReq = FountainRuntime.HTTPRequest(method: "POST", path: "/zones/\(zone.id)/records", headers: ["Content-Type": "application/json"], body: try JSONEncoder().encode(["name": "www", "type": "A", "value": "1.2.3.4"]))
        let cr = await server.createRecord(zone.id, request: recReq)
        XCTAssertEqual(cr.status, 201)
        struct Rec: Decodable { let id: String; let name: String; let type: String; let value: String }
        let created = try JSONDecoder().decode(Rec.self, from: cr.body)

        // List records
        let lr = await server.listRecords(zone.id)
        XCTAssertEqual(lr.status, 200)

        // Update record
        let updReq = FountainRuntime.HTTPRequest(method: "PUT", path: "/zones/\(zone.id)/records/\(created.id)", headers: ["Content-Type": "application/json"], body: try JSONEncoder().encode(["name": "www", "type": "A", "value": "4.3.2.1"]))
        let ur = await server.updateRecord(zone.id, recordId: created.id, request: updReq)
        XCTAssertEqual(ur.status, 200)

        // Delete record
        let dr = await server.deleteRecord(zone.id, recordId: created.id)
        XCTAssertEqual(dr.status, 204)

        // Error path: listing records for unknown zone
        let notFound = await server.listRecords(UUID().uuidString)
        XCTAssertEqual(notFound.status, 404)
    }
}
