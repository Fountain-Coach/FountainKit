import Foundation

/// Minimal circuit breaker protecting the LLM sentinel.
actor CircuitBreaker {
    private let failureThreshold: Int
    private let openInterval: TimeInterval
    private var failures: Int = 0
    private var openedAt: Date?

    init(failureThreshold: Int = 3, openInterval: TimeInterval = 30) {
        self.failureThreshold = failureThreshold
        self.openInterval = openInterval
    }

    /// Returns `true` if requests are allowed.
    func allow() -> Bool {
        if let openedAt = openedAt {
            if Date().timeIntervalSince(openedAt) > openInterval {
                self.openedAt = nil
                self.failures = 0
                return true
            } else {
                return false
            }
        }
        return true
    }

    /// Records a successful call, resetting internal state.
    func recordSuccess() {
        failures = 0
        openedAt = nil
    }

    /// Records a failed call. Opens the breaker when the
    /// failure threshold is reached.
    func recordFailure() {
        failures += 1
        if failures >= failureThreshold {
            openedAt = Date()
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
