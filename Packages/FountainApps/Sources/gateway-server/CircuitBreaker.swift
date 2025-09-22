import Foundation

public actor CircuitBreaker {
    public enum State: String { case closed, open, halfOpen }
    public struct Config: Sendable {
        public let failureThreshold: Int
        public let resetTimeoutSeconds: Int
        public let halfOpenMaxAttempts: Int
        public init(failureThreshold: Int = Int(ProcessInfo.processInfo.environment["GATEWAY_CB_FAILURES"] ?? "5") ?? 5,
                    resetTimeoutSeconds: Int = Int(ProcessInfo.processInfo.environment["GATEWAY_CB_RESET_SECS"] ?? "10") ?? 10,
                    halfOpenMaxAttempts: Int = Int(ProcessInfo.processInfo.environment["GATEWAY_CB_HALFOPEN_ATTEMPTS"] ?? "1") ?? 1) {
            self.failureThreshold = failureThreshold
            self.resetTimeoutSeconds = resetTimeoutSeconds
            self.halfOpenMaxAttempts = halfOpenMaxAttempts
        }
    }

    private struct Entry { var state: State; var failures: Int; var openedAt: Date; var halfOpenAttempts: Int }
    private var table: [String: Entry] = [:]
    private let config: Config
    private var openRejects: Int = 0
    private var opens: Int = 0

    public init(config: Config = Config()) { self.config = config }

    public func allow(key: String) -> Bool {
        if var e = table[key] {
            switch e.state {
            case .closed:
                return true
            case .open:
                if Date().timeIntervalSince(e.openedAt) >= TimeInterval(config.resetTimeoutSeconds) {
                    e.state = .halfOpen; e.halfOpenAttempts = 0; table[key] = e; return true
                } else {
                    openRejects += 1; return false
                }
            case .halfOpen:
                if e.halfOpenAttempts < config.halfOpenMaxAttempts {
                    e.halfOpenAttempts += 1; table[key] = e; return true
                } else {
                    openRejects += 1; return false
                }
            }
        }
        return true
    }

    public func recordSuccess(key: String) {
        table[key] = Entry(state: .closed, failures: 0, openedAt: Date(timeIntervalSince1970: 0), halfOpenAttempts: 0)
    }

    public func recordFailure(key: String) {
        if var e = table[key] {
            e.failures += 1
            if e.failures >= config.failureThreshold { e.state = .open; e.openedAt = Date(); opens += 1 }
            table[key] = e
        } else {
            var e = Entry(state: .closed, failures: 1, openedAt: Date(), halfOpenAttempts: 0)
            if e.failures >= config.failureThreshold { e.state = .open; opens += 1 }
            table[key] = e
        }
    }

    public func metrics() -> [String: Int] {
        [
            "gateway_cb_opens_total": opens,
            "gateway_cb_rejects_total": openRejects
        ]
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

