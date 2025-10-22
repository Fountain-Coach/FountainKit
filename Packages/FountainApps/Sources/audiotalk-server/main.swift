import Foundation
import Dispatch
import FountainRuntime
import AudioTalkService
import LauncherSignature
import FountainStoreClient

let env = ProcessInfo.processInfo.environment
if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

func resolveStoreRoot(from env: [String: String]) -> URL {
    if let override = env["FOUNTAINSTORE_DIR"], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let expanded: String
        if override.hasPrefix("~") { expanded = FileManager.default.homeDirectoryForCurrentUser.path + String(override.dropFirst()) } else { expanded = override }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return cwd.appendingPathComponent(".fountain/store", isDirectory: true)
}

Task {
    // Serve generated OpenAPI handlers via NIO bridge with fallback that serves the spec
    let fallback = HTTPKernel { req in
        if req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-AudioTalk/Sources/AudioTalkService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        } else if req.path == "/" || req.path == "/index.html" {
            let url = URL(fileURLWithPath: "Packages/FountainApps/Sources/audiotalk-server/Static/index.html")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    // Resolve persistence (disk-backed when possible; falls back to embedded).
    let svc: FountainStoreClient = {
        let root = resolveStoreRoot(from: env)
        do {
            let disk = try DiskFountainStoreClient(rootDirectory: root)
            print("audiotalk: using disk store at \(root.path)")
            return FountainStoreClient(client: disk)
        } catch {
            FileHandle.standardError.write(Data("[audiotalk] WARN: falling back to in-memory store (\(error))\n".utf8))
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }
    }()
    let corpusId = env["AUDIOTALK_CORPUS_ID"] ?? env["DEFAULT_CORPUS_ID"] ?? "audiotalk"
    let api = AudioTalkOpenAPI(store: svc, corpusId: corpusId)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    do {
        let port = Int(env["AUDIOTALK_PORT"] ?? env["PORT"] ?? "8080") ?? 8080
        _ = try await server.start(port: port)
        print("audiotalk-server listening on port \(port)")
    } catch {
        FileHandle.standardError.write(Data("[audiotalk] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
