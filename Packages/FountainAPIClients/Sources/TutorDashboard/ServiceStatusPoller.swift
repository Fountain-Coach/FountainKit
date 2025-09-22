import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ApiClientsCore

public struct ServiceStatus: Sendable, Equatable {
    public struct EndpointStatus: Sendable, Equatable {
        public let path: String
        public let ok: Bool
        public let statusCode: Int?
        public let message: String?
        public let capabilities: [String]
        public let missingCapabilities: [String]

        public init(
            path: String,
            ok: Bool,
            statusCode: Int?,
            message: String?,
            capabilities: [String] = [],
            missingCapabilities: [String] = []
        ) {
            self.path = path
            self.ok = ok
            self.statusCode = statusCode
            self.message = message
            self.capabilities = capabilities
            self.missingCapabilities = missingCapabilities
        }
    }

    public let descriptor: ServiceDescriptor
    public let baseURL: URL
    public let health: [EndpointStatus]
    public let capabilities: [EndpointStatus]

    public init(descriptor: ServiceDescriptor, baseURL: URL, health: [EndpointStatus], capabilities: [EndpointStatus]) {
        self.descriptor = descriptor
        self.baseURL = baseURL
        self.health = health
        self.capabilities = capabilities
    }

    public var isHealthy: Bool {
        health.allSatisfy { $0.ok }
    }
}

public struct ServiceStatusPoller: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchStatus(
        for descriptors: [ServiceDescriptor],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> [ServiceStatus] {
        var statuses: [ServiceStatus] = []

        for descriptor in descriptors {
            guard let base = descriptor.resolveBaseURL(environment: environment) else { continue }
            let client = RESTClient(baseURL: base, session: session)
            var healthStatuses: [ServiceStatus.EndpointStatus] = []
            for path in descriptor.healthPaths {
                let status = await fetchEndpoint(path: path, isCapabilities: false, client: client)
                healthStatuses.append(status)
            }

            var capabilityStatuses: [ServiceStatus.EndpointStatus] = []
            for path in descriptor.capabilityPaths {
                let status = await fetchEndpoint(path: path, isCapabilities: true, client: client)
                capabilityStatuses.append(status)
            }

            let combined = ServiceStatus(
                descriptor: descriptor,
                baseURL: base,
                health: healthStatuses,
                capabilities: capabilityStatuses
            )
            statuses.append(combined)
        }

        return statuses.sorted { $0.descriptor.title < $1.descriptor.title }
    }

    private func fetchEndpoint(path: String, isCapabilities: Bool, client: RESTClient) async -> ServiceStatus.EndpointStatus {
        guard let url = client.buildURL(path: path) else {
            return ServiceStatus.EndpointStatus(
                path: path,
                ok: false,
                statusCode: nil,
                message: "Invalid URL",
                capabilities: []
            )
        }

        do {
            let response = try await client.send(APIRequest(method: .GET, url: url))
            let capabilities: ([String], [String])
            if isCapabilities {
                capabilities = Self.parseCapabilities(from: response.data)
            } else {
                capabilities = ([], [])
            }
            return ServiceStatus.EndpointStatus(
                path: path,
                ok: true,
                statusCode: response.status,
                message: nil,
                capabilities: capabilities.0,
                missingCapabilities: capabilities.1
            )
        } catch let APIError.httpStatus(code, body) {
            let message = body.isEmpty ? nil : body
            return ServiceStatus.EndpointStatus(
                path: path,
                ok: false,
                statusCode: code,
                message: message,
                capabilities: []
            )
        } catch {
            return ServiceStatus.EndpointStatus(
                path: path,
                ok: false,
                statusCode: nil,
                message: error.localizedDescription,
                capabilities: []
            )
        }
    }

    private static func parseCapabilities(from data: Data) -> ([String], [String]) {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ([], []) }

        var available: [String] = []
        var missing: [String] = []
        for (key, value) in object {
            if isCapabilitySatisfied(value) {
                available.append(key)
            } else {
                missing.append(key)
            }
        }

        return (available.sorted(), missing.sorted())
    }

    private static func isCapabilitySatisfied(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let string as String:
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let array as [Any]:
            return !array.isEmpty
        case let dict as [String: Any]:
            return !dict.isEmpty
        case let number as NSNumber:
            return number.doubleValue != 0
        default:
            return false
        }
    }
}
