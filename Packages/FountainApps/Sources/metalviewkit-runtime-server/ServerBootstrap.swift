import Foundation
import OpenAPIRuntime

public enum MetalViewKitRuntimeServer {
    public static func register(on transport: any ServerTransport) throws {
        let handlers = MVKRuntimeHandlers()
        try handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    }
}

