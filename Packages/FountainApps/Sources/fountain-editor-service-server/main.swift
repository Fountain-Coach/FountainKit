import Foundation
import Dispatch
import FountainRuntime
import LauncherSignature
import FountainStoreClient
import OpenAPIRuntime
import Darwin

let env = ProcessInfo.processInfo.environment
let SMOKE_TIMEOUT: Double = {
    if let s = env["SMOKE_TIMEOUT_SECS"], let v = Double(s), v > 0 { return v }
    if let s = env["FK_SMOKE_TIMEOUT"], let v = Double(s), v > 0 { return v }
    return 5.0
}()

struct TimeoutError: Error {}

func withTimeout<T>(_ seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// Smoke mode FIRST: bypass any signature checks or long inits.
if env["FK_EDITOR_SMOKE"] == "1" {
    func runSmoke() async -> Int32 {
        FileHandle.standardError.write(Data("[smoke] starting in-process kernel…\n".utf8))
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        guard let disk = try? DiskFountainStoreClient(rootDirectory: tmp) else { fputs("[smoke] disk store failed\n", stderr); return 2 }
        let store = FountainStoreClient(client: disk)
        let transport = NIOOpenAPIServerTransport()
        let handlers = FountainEditorHandlers(store: store)
        do {
            try handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
        } catch {
            FileHandle.standardError.write(Data("[smoke] registerHandlers failed: \(error)\n".utf8))
            return 2
        }
        let kernel = transport.asKernel()
        let cid = "fountain-editor"
        // Create with If-Match: "*"
        do {
            FileHandle.standardError.write(Data("[smoke] PUT create…\n".utf8))
            let body = Data("Hello".utf8)
            let req = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
                "If-Match": "*",
                "Content-Type": "text/plain",
                "Content-Length": String(body.count)
            ], body: body)
            let resp = try await withTimeout(SMOKE_TIMEOUT) { try await kernel.handle(req) }
            if resp.status != 204 { fputs("[smoke] expected 204 create, got \(resp.status)\n", stderr); return 3 }
        } catch { fputs("[smoke] PUT create error: \(error)\n", stderr); return 3 }
        // GET with ETag
        let etag1: String
        do {
            FileHandle.standardError.write(Data("[smoke] GET script…\n".utf8))
            let getResp = try await withTimeout(SMOKE_TIMEOUT) { try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script")) }
            if getResp.status != 200 { fputs("[smoke] expected 200 GET, got \(getResp.status)\n", stderr); return 4 }
            etag1 = getResp.headers["ETag"] ?? ""
            if etag1.count != 8 { fputs("[smoke] bad ETag length\n", stderr); return 4 }
        } catch { fputs("[smoke] GET error: \(error)\n", stderr); return 4 }
        // Mismatched If-Match -> 412
        do {
            FileHandle.standardError.write(Data("[smoke] PUT mismatch…\n".utf8))
            let body = Data("Hello again".utf8)
            let req = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
                "If-Match": "deadbeef",
                "Content-Type": "text/plain",
                "Content-Length": String(body.count)
            ], body: body)
            let resp = try await withTimeout(SMOKE_TIMEOUT) { try await kernel.handle(req) }
            if resp.status != 412 { fputs("[smoke] expected 412 mismatch, got \(resp.status)\n", stderr); return 5 }
        } catch { fputs("[smoke] PUT mismatch error: \(error)\n", stderr); return 5 }
        // Correct If-Match -> 204 and ETag changes
        do {
            FileHandle.standardError.write(Data("[smoke] PUT update…\n".utf8))
            let body = Data("Hello world!".utf8)
            let req = HTTPRequest(method: "PUT", path: "/editor/\(cid)/script", headers: [
                "If-Match": etag1,
                "Content-Type": "text/plain",
                "Content-Length": String(body.count)
            ], body: body)
            let resp = try await withTimeout(SMOKE_TIMEOUT) { try await kernel.handle(req) }
            if resp.status != 204 { fputs("[smoke] expected 204 update, got \(resp.status)\n", stderr); return 6 }
            let getResp = try await withTimeout(SMOKE_TIMEOUT) { try await kernel.handle(HTTPRequest(method: "GET", path: "/editor/\(cid)/script")) }
            let etag2 = getResp.headers["ETag"] ?? ""
            if etag2 == etag1 || etag2.count != 8 { fputs("[smoke] ETag did not change\n", stderr); return 6 }
        } catch { fputs("[smoke] PUT update error: \(error)\n", stderr); return 6 }
        print("[smoke] fountain-editor-server ETag flow OK")
        return 0
    }
    Task {
        let status = await runSmoke()
        Darwin.exit(status)
    }
    dispatchMain()
}

// Only verify launcher signature for normal server mode (not smoke).
if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

// Serve generated OpenAPI + a tiny fallback to the spec
let transport = NIOOpenAPIServerTransport(fallback: HTTPKernel { req in
    if req.path == "/openapi.yaml" {
        let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/fountain-editor-service/openapi.yaml")
        if let data = try? Data(contentsOf: url) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
        }
    }
    return HTTPResponse(status: 404)
})

// Resolve FountainStore
let store: FountainStoreClient = {
    let root: URL = {
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if dir.hasPrefix("~") { return URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true) }
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(".fountain/store", isDirectory: true)
    }()
    do {
        let disk = try DiskFountainStoreClient(rootDirectory: root)
        return FountainStoreClient(client: disk)
    } catch {
        FileHandle.standardError.write(Data("[fountain-editor] WARN: falling back to in-memory store (\(error))\n".utf8))
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }
}()

// Register generated handlers
let handlers = FountainEditorHandlers(store: store)
try? handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)

let server = NIOHTTPServer(kernel: transport.asKernel())
Task {
    do {
        let port = Int(env["FOUNTAIN_EDITOR_PORT"] ?? env["PORT"] ?? "8080") ?? 8080
        _ = try await server.start(port: port)
        print("fountain-editor-server listening on port \(port)")
    } catch {
        FileHandle.standardError.write(Data("[fountain-editor] start failed: \(error)\n".utf8))
    }
}
dispatchMain()
