import Foundation

public actor GatewayRequestMetrics {
    public static let shared = GatewayRequestMetrics()

    private var total: Int = 0
    private var byMethod: [String: Int] = [:]
    private var byStatus: [Int: Int] = [:]

    public func record(method: String, status: Int) {
        total += 1
        byMethod[method, default: 0] += 1
        byStatus[status, default: 0] += 1
    }

    public func snapshot() -> [String: Int] {
        var out: [String: Int] = ["gateway_requests_total": total]
        for (m, v) in byMethod { out["gateway_requests_method_\(m)_total"] = v }
        for (s, v) in byStatus { out["gateway_responses_status_\(s)_total"] = v }
        return out
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

