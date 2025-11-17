import Foundation
import FountainStoreClient
import AwarenessService
import FountainRuntime
import LauncherSignature

if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" { verifyLauncherSignature() }

let env = ProcessInfo.processInfo.environment
let corpusId = env["DEFAULT_CORPUS_ID"] ?? "tools-factory"

func resolveStoreRoot(from env: [String: String]) -> URL {
    if let override = env["FOUNTAINSTORE_DIR"], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let expanded: String
        if override.hasPrefix("~") { expanded = FileManager.default.homeDirectoryForCurrentUser.path + String(override.dropFirst()) } else { expanded = override }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return cwd.appendingPathComponent(".fountain/store", isDirectory: true)
}

let svc: FountainStoreClient = {
    let root = resolveStoreRoot(from: env)
    do {
        let disk = try DiskFountainStoreClient(rootDirectory: root)
        print("baseline-awareness: using disk store at \(root.path)")
        return FountainStoreClient(client: disk)
    } catch {
        FileHandle.standardError.write(Data("[baseline-awareness] WARN: falling back to in-memory store (\(error))\n".utf8))
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }
}()

Task {
    // Serve generated OpenAPI handlers via NIO transport with a small fallback.
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-Awareness/Sources/AwarenessService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = AwarenessOpenAPI(persistence: svc)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    do {
        let port = Int(env["BASELINE_AWARENESS_PORT"] ?? env["PORT"] ?? "8001") ?? 8001
        _ = try await server.start(port: port)
        print("baseline-awareness (NIO) listening on :\(port)")
    } catch {
        FileHandle.standardError.write(Data("[baseline-awareness] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
