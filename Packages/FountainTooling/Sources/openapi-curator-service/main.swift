import Foundation
import Dispatch
import FountainRuntime
import LauncherSignature

verifyLauncherSignature()

let server = NIOHTTPServer(kernel: makeOpenAPICuratorKernel())
Task {
    do {
        _ = try await server.start(port: 8000)
        print("openapi-curator service listening on port 8000")
    } catch {
        FileHandle.standardError.write(Data("[openapi-curator] Failed to start: \(error)\n".utf8))
    }
}
dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
