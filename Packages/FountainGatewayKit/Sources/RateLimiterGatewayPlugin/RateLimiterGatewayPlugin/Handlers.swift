import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FountainRuntime

public protocol LLMClient: Sendable {
    func call(prompt: String) async throws -> String
}

/// Handlers for rate limiter gateway endpoints using an LLM backend.
public actor Handlers {
    private let client: LLMClient
    private let defaultLimit: Int
    private let date: @Sendable () -> Date
    private var buckets: [String: (minute: Int, count: Int)] = [:]
    private var allowedTotal = 0
    private var throttledTotal = 0

    public init(defaultLimit: Int = 60,
                client: LLMClient? = nil,
                date: @Sendable @escaping () -> Date = Date.init) {
        self.defaultLimit = defaultLimit
        self.client = client ?? LLMPluginClient(personaPath: "openapi/personas/rate-limiter.md")
        self.date = date
    }

    /// Returns whether the request is within its rate limit.
    public func allow(routeId: String, clientId: String, limitPerMinute: Int?) async -> Bool {
        let req = RateLimitCheckRequest(routeId: routeId,
                                        clientId: clientId,
                                        limitPerMinute: limitPerMinute ?? defaultLimit)
        let prompt = (try? String(data: JSONEncoder().encode(req), encoding: .utf8)) ?? ""
        let allowed: Bool
        if let result = try? await client.call(prompt: prompt),
           let data = result.data(using: .utf8),
           let resp = try? JSONDecoder().decode(RateLimitCheckResponse.self, from: data) {
            allowed = resp.allowed
        } else {
            allowed = localAllow(routeId: routeId, clientId: clientId, limit: limitPerMinute ?? defaultLimit)
        }
        await DNSMetrics.shared.recordRateLimit(allowed: allowed)
        return allowed
    }

    /// Returns aggregate allowance statistics.
    public func stats() async -> (allowed: Int, throttled: Int) {
        if let result = try? await client.call(prompt: "stats"),
           let data = result.data(using: .utf8),
           let resp = try? JSONDecoder().decode(RateLimitStatsResponse.self, from: data) {
            return (resp.allowed, resp.throttled)
        }
        return (allowedTotal, throttledTotal)
    }

    /// Delegates rate limit checks to the LLM via HTTP.
    public func rateLimitCheck(_ request: HTTPRequest, body: RateLimitCheckRequest?) async throws -> HTTPResponse {
        let allowed = await allow(routeId: body?.routeId ?? "",
                                  clientId: body?.clientId ?? "",
                                  limitPerMinute: body?.limitPerMinute)
        let resp = RateLimitCheckResponse(allowed: allowed)
        let json = try JSONEncoder().encode(resp)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
    }

    /// Requests aggregated statistics from the LLM via HTTP.
    public func rateLimitStats(_ request: HTTPRequest, body: NoBody?) async throws -> HTTPResponse {
        let s = await stats()
        let resp = RateLimitStatsResponse(allowed: s.allowed, throttled: s.throttled)
        let json = try JSONEncoder().encode(resp)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
    }

    private func localAllow(routeId: String, clientId: String, limit: Int) -> Bool {
        let key = "\(routeId)|\(clientId)"
        let minute = Int(date().timeIntervalSince1970 / 60)
        var bucket = buckets[key] ?? (minute: minute, count: 0)
        if bucket.minute != minute {
            bucket = (minute: minute, count: 0)
        }
        if bucket.count < limit {
            bucket.count += 1
            buckets[key] = bucket
            allowedTotal += 1
            return true
        } else {
            throttledTotal += 1
            buckets[key] = bucket
            return false
        }
    }
}

/// Minimal client that forwards prompts and persona to the LLM Gateway.
struct LLMPluginClient {
    let persona: String
    let url: URL

    init(personaPath: String,
         url: URL = URL(string: ProcessInfo.processInfo.environment["LLM_GATEWAY_URL"] ?? "http://localhost:8080/chat")!) {
        self.persona = (try? String(contentsOfFile: personaPath, encoding: .utf8)) ?? ""
        self.url = url
    }

    func call(prompt: String) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["persona": persona, "prompt": prompt]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

extension LLMPluginClient: LLMClient {}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
