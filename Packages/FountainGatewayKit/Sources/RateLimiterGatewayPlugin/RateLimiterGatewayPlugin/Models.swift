import Foundation

/// Request to check a route's rate limit.
public struct RateLimitCheckRequest: Codable {
    public let routeId: String
    public let clientId: String
    public let limitPerMinute: Int?
    public init(routeId: String, clientId: String, limitPerMinute: Int? = nil) {
        self.routeId = routeId
        self.clientId = clientId
        self.limitPerMinute = limitPerMinute
    }
}

/// Response indicating if a request is allowed.
public struct RateLimitCheckResponse: Codable {
    public let allowed: Bool
    public init(allowed: Bool) { self.allowed = allowed }
}

/// Response containing aggregate rate limiter statistics.
public struct RateLimitStatsResponse: Codable {
    public let allowed: Int
    public let throttled: Int
    public init(allowed: Int, throttled: Int) {
        self.allowed = allowed
        self.throttled = throttled
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
