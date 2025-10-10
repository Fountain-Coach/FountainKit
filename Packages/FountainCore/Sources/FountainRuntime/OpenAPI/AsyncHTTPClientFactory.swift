import Foundation
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import AsyncHTTPClient

extension OpenAPIClientFactory {
    /// Build an AsyncHTTPClient-based OpenAPI transport using a provided HTTPClient.
    /// - Parameters:
    ///   - defaultHeaders: Header dictionary to inject when missing.
    ///   - httpClient: A configured AsyncHTTPClient instance owned by the caller.
    /// - Returns: Tuple of (transport, middlewares).
    public static func makeAsyncHTTPClientTransport(
        defaultHeaders: [String: String] = [:],
        httpClient: HTTPClient
    ) -> (transport: AsyncHTTPClientTransport, middlewares: [any ClientMiddleware]) {
        let transport = AsyncHTTPClientTransport(httpClient: httpClient)
        let mws = defaultMiddlewares(defaultHeaders: defaultHeaders)
        return (transport, mws)
    }

    /// Build an AsyncHTTPClient-based OpenAPI transport with an internally created HTTPClient.
    /// The created client is returned so the caller can manage its lifecycle (shutdown when done).
    /// - Parameters:
    ///   - defaultHeaders: Header dictionary to inject when missing.
    ///   - configuration: HTTPClient configuration.
    ///   - eventLoopGroupProvider: Event loop group provider for HTTPClient.
    /// - Returns: Tuple of (transport, middlewares, httpClient).
    public static func makeOwnedAsyncHTTPClientTransport(
        defaultHeaders: [String: String] = [:],
        configuration: HTTPClient.Configuration = .init(),
        eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider = .createNew
    ) -> (transport: AsyncHTTPClientTransport, middlewares: [any ClientMiddleware], httpClient: HTTPClient) {
        let client = HTTPClient(eventLoopGroupProvider: eventLoopGroupProvider, configuration: configuration)
        let transport = AsyncHTTPClientTransport(httpClient: client)
        let mws = defaultMiddlewares(defaultHeaders: defaultHeaders)
        return (transport, mws, client)
    }
}

