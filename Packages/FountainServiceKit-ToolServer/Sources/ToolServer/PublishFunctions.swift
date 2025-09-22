import Foundation
import FountainStoreClient

public enum PublishError: Error { case empty }

public func publishFunctions(manifest: ToolManifest, corpusId: String, service: FountainStoreClient) async throws {
    let ops = manifest.operations
    if ops.isEmpty { throw PublishError.empty }
    for op in ops {
        let fn = FunctionModel(corpusId: corpusId, functionId: op, name: op, description: "Tools Factory operation", httpMethod: "POST", httpPath: "/\(op)")
        _ = try await service.addFunction(fn)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

