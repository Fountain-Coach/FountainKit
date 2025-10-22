import Foundation
import FountainStoreClient
import ToolsFactoryService
import FountainRuntime
import LauncherSignature

verifyLauncherSignature()

let manifestURL = URL(fileURLWithPath: "tools.json")
let manifest = (try? ToolManifest.load(from: manifestURL)) ?? ToolManifest(image: .init(name: "", tarball: "", sha256: "", qcow2: "", qcow2_sha256: ""), tools: [:], operations: [])
let env = ProcessInfo.processInfo.environment
let corpusId = env["TOOLS_FACTORY_CORPUS_ID"] ?? env["DEFAULT_CORPUS_ID"] ?? "tools-factory"

let svc: FountainStoreClient = {
    if let dir = env["FOUNTAINSTORE_DIR"], !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let url: URL
        if dir.hasPrefix("~") {
            url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
        } else { url = URL(fileURLWithPath: dir, isDirectory: true) }
        if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
            return FountainStoreClient(client: disk)
        }
    }
    return FountainStoreClient(client: EmbeddedFountainStoreClient())
}()
Task {
    await svc.ensureCollections(corpusId: corpusId)
    try? await publishFunctions(manifest: manifest, corpusId: corpusId, service: svc)
    // Fallback serves metrics and the spec.
    let fallback = HTTPKernel { req in
        if req.method == "GET" && req.path == "/metrics" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8))
        }
        if req.method == "GET" && req.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainServiceKit-ToolsFactory/Sources/ToolsFactoryService/openapi.yaml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
        }
        return HTTPResponse(status: 404)
    }
    let transport = NIOOpenAPIServerTransport(fallback: fallback)
    let api = ToolsFactoryOpenAPI(persistence: svc)
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    let server = NIOHTTPServer(kernel: transport.asKernel())
    do {
        let port = Int(ProcessInfo.processInfo.environment["TOOLS_FACTORY_PORT"] ?? ProcessInfo.processInfo.environment["PORT"] ?? "8011") ?? 8011
        _ = try await server.start(port: port)
        print("tools-factory (NIO) listening on :\(port)")
    } catch {
        FileHandle.standardError.write(Data("[tools-factory] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
