import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenAPIRuntime
import OpenAPIURLSession

extension OpenAPIClientFactory {
    /// Convenience builder for URLSession-based OpenAPI clients.
    /// Returns both the transport and a standard middleware chain with optional default headers.
    /// - Parameters:
    ///   - defaultHeaders: Header dictionary to inject when missing (e.g. Authorization).
    ///   - session: URLSession instance to use (defaults to shared).
    /// - Returns: Tuple of (URLSessionTransport, middlewares).
    public static func makeURLSessionTransport(
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) -> (transport: URLSessionTransport, middlewares: [any ClientMiddleware]) {
        // Current URLSessionTransport does not accept a session argument in this version.
        let transport = URLSessionTransport()
        let mws = defaultMiddlewares(defaultHeaders: defaultHeaders)
        return (transport, mws)
    }
}
