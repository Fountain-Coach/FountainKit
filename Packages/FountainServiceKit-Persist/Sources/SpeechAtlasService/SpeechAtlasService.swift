import Foundation
import OpenAPIRuntime

/// Placeholder handlers for the Four Stars speech atlas surface.
///
/// TODO: Thread this through `FountainStoreClient` once the underlying persistence
/// queries are implemented. For now we return 501 so studios can link against
/// the generated interfaces while the implementation comes together.
public struct SpeechAtlasHandlers: APIProtocol, @unchecked Sendable {
    public init() {}

    public func speechesList(_ input: Operations.speechesList.Input) async throws -> Operations.speechesList.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func speechesDetail(_ input: Operations.speechesDetail.Input) async throws -> Operations.speechesDetail.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }

    public func speechesSummary(_ input: Operations.speechesSummary.Input) async throws -> Operations.speechesSummary.Output {
        .undocumented(statusCode: 501, OpenAPIRuntime.UndocumentedPayload())
    }
}
