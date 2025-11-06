import Foundation
import OpenAPIRuntime

public enum MetalViewKitRuntimeServer {
    public static let sharedCore = MVKRuntimeCore()
    public static func register(on transport: any ServerTransport) throws {
        let handlers = MVKRuntimeHandlers(core: sharedCore)
        try handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    }
}
