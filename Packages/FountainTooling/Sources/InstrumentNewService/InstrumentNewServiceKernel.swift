import Foundation
import FountainRuntime

/// Build an HTTPKernel for the Instrument New OpenAPI service.
public func makeInstrumentNewKernel() -> HTTPKernel {
    let transport = NIOOpenAPIServerTransport()
    let api = InstrumentNewOpenAPI()
    try? api.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    return transport.asKernel()
}

