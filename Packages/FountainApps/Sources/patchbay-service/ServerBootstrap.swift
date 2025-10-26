import Foundation
import OpenAPIRuntime

public enum PatchBayServer {
    public static func register(on transport: any ServerTransport) throws {
        let handlers = PatchBayHandlers()
        try handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    }
}

