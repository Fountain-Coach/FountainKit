import Foundation
import OpenAPIRuntime
import QCMockServiceCore

public enum QCMockServer {
    /// Registers qc-mock-service handlers onto a ServerTransport.
    public static func register(on transport: any ServerTransport) throws {
        let handlers = QCMockHandlers(core: QCMockServiceCore.ServiceCore())
        try handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    }
}
