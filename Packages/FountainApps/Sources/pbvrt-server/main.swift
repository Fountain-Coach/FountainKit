import Foundation
import FountainRuntime
import FountainStoreClient
import LauncherSignature

let env = ProcessInfo.processInfo.environment
if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

func resolveStore() -> FountainStoreClient {
    if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
        let url: URL
        if dir.hasPrefix("~") {
            url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
        } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
        if let disk = try? DiskFountainStoreClient(rootDirectory: url) { return FountainStoreClient(client: disk) }
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
        return FountainStoreClient(client: disk)
    }
    return FountainStoreClient(client: EmbeddedFountainStoreClient())
}

let store = resolveStore()

let kernel = HTTPKernel { req in
    // Base prefix from spec servers.url
    let base = "/pb-vrt"
    if req.path == base + "/openapi.yaml" || req.path == "/openapi.yaml" {
        let url = URL(fileURLWithPath: "Packages/FountainSpecCuration/openapi/v1/pb-vrt.yml")
        if let data = try? Data(contentsOf: url) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
        }
        return HTTPResponse(status: 404)
    }
    if req.path == base + "/health" || req.path == "/health" {
        let data = Data("{\"status\":\"ok\"}".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }
    // Future: implement /prompts, /baselines, /compare, /probes routes.
    return HTTPResponse(status: 501)
}

let server = NIOHTTPServer(kernel: kernel)
Task {
    do {
        let port = Int(env["PBVRT_PORT"] ?? env["PORT"] ?? "8010") ?? 8010
        _ = try await server.start(port: port)
        print("pbvrt-server listening on port \(port) — spec at /pb-vrt/openapi.yaml")
    } catch {
        FileHandle.standardError.write(Data("[pbvrt-server] start failed: \(error)\n".utf8))
    }
}
import Dispatch
dispatchMain()

