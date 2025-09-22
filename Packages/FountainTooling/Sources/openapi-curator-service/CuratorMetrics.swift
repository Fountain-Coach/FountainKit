import Foundation

/// Actor-backed container for Curator service metrics.
actor CuratorMetrics {
    private var opsKept = 0
    private var opsRemoved = 0
    private var opsRenamed = 0
    private var collisions = 0
    private var submitSuccess = 0
    private var submitError = 0

    /// Record operation stats for a curation run.
    func recordCurate(kept: Int, removed: Int, renamed: Int, collisions: Int) {
        self.opsKept += kept
        self.opsRemoved += removed
        self.opsRenamed += renamed
        self.collisions += collisions
    }

    /// Record Tools Factory submission outcome.
    func recordSubmit(success: Bool) {
        if success {
            submitSuccess += 1
        } else {
            submitError += 1
        }
    }

    /// Snapshot current metrics values.
    func snapshot() -> (kept: Int, removed: Int, renamed: Int, collisions: Int, submitSuccess: Int, submitError: Int) {
        (opsKept, opsRemoved, opsRenamed, collisions, submitSuccess, submitError)
    }
}

/// Global metrics instance used by the Curator service.
let curatorMetrics = CuratorMetrics()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.

