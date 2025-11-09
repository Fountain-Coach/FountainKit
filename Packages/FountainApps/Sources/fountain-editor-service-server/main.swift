import Foundation
import Dispatch
import FountainRuntime
import LauncherSignature
import FountainStoreClient
import OpenAPIRuntime

let env = ProcessInfo.processInfo.environment
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
