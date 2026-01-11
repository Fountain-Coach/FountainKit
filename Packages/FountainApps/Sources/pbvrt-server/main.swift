import Foundation
import FountainRuntime
import FountainStoreClient
import LauncherSignature
import OpenAPIRuntime

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
let transport = NIOOpenAPIServerTransport(fallback: HTTPKernel { req in
    if req.path == "/pb-vrt/openapi.yaml" || req.path == "/openapi.yaml" {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "Packages/FountainSpecCuration/openapi/v1/fcis-vrt-render.yml")) {
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
        }
    }
    return HTTPResponse(status: 404)
})

// Register generated handlers (implemented in Handlers.swift)
let corpusId = env["PBVRT_CORPUS_ID"] ?? env["DEFAULT_CORPUS_ID"] ?? "pb-vrt"
let artifactsRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    .appendingPathComponent(".fountain/artifacts/pb-vrt", isDirectory: true)
try? FileManager.default.createDirectory(at: artifactsRoot, withIntermediateDirectories: true)
let handlers = PBVRTHandlers(store: store, corpusId: corpusId, artifactsRoot: artifactsRoot)
try? handlers.registerHandlers(on: transport, serverURL: URL(string: "/pb-vrt")!)

let server = NIOHTTPServer(kernel: transport.asKernel())
Task {
    do {
        let port = Int(env["PBVRT_PORT"] ?? env["PORT"] ?? "8010") ?? 8010
        _ = try await server.start(port: port)
        print("pbvrt-server (FCIS-VRT Render, legacy path) listening on port \(port) — spec at /pb-vrt/openapi.yaml")
    } catch {
        FileHandle.standardError.write(Data("[pbvrt-server] start failed: \(error)\n".utf8))
    }
}
import Dispatch
dispatchMain()
