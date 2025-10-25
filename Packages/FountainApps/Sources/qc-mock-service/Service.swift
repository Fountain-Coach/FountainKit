import Foundation
import QCMockServiceCore

public enum QCMockServiceSelfTest {
    public static func runSync() throws {
        let sem = DispatchSemaphore(value: 0)
        var caught: Error? = nil
        Task {
            do { try await run(); sem.signal() } catch { caught = error; sem.signal() }
        }
        sem.wait()
        if let e = caught { throw e }
    }

    static func run() async throws {
        let core = ServiceCore(docWidth: 1000, docHeight: 800, gridStep: 20)
        let h = QCMockHandlers(core: core)
        // Health
        guard case .ok = try await h.getHealth(Operations.getHealth.Input()) else { throw SelfTestError.failure("health") }
        // Zoom + pan roundtrip
        let z = Operations.zoomSet.Input.Body.jsonPayload(scale: 2.0, anchorView: nil)
        _ = try await h.zoomSet(.init(body: .json(z)))
        let p = Operations.panBy.Input.Body.jsonPayload(dx: 5, dy: -3)
        _ = try await h.panBy(.init(body: .json(p)))
        let c = try await h.getCanvas(.init())
        if case let .ok(ok) = c { let s = try ok.body.json; assertClose(s.transform.scale, 2.0); assertClose(s.transform.translation.x, 5.0); assertClose(s.transform.translation.y, -3.0) } else { throw SelfTestError.failure("canvas") }
        // Node + port + edge + export/import
        let cn = Components.Schemas.CreateNode(id: "n1", title: "A", x: 10, y: 20, w: 100, h: 60, ports: [])
        let created = try await h.createNode(.init(body: .json(cn)))
        guard case .created = created else { throw SelfTestError.failure("createNode") }
        let port = Components.Schemas.Port(id: "p1", side: .left, dir: .out, _type: .data)
        let upd = try await h.addPort(.init(path: .init(id: "n1"), headers: .init(), body: .json(port)))
        guard case .ok = upd else { throw SelfTestError.failure("addPort") }
        let ceBody = Components.Schemas.CreateEdge(from: "n1.p1", to: "n1.p1", routing: .qcBezier)
        let ce = try await h.createEdge(.init(body: .json(ceBody)))
        guard case .created = ce else { throw SelfTestError.failure("createEdge") }
        let doc = try await h.exportJSON(.init())
        guard case .ok = doc else { throw SelfTestError.failure("exportJSON") }
    }

    enum SelfTestError: Error { case failure(String) }
    static func assertClose(_ a: Double, _ b: Double, eps: Double = 1e-4) {
        precondition(abs(a - b) <= eps, "Assertion failed: \(a) vs \(b)")
    }
}
