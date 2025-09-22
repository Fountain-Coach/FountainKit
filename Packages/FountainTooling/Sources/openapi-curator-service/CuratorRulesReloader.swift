import Foundation

/// Periodically checks the curator rules file and triggers reloads on change.
final class CuratorRulesReloader: @unchecked Sendable {
    private let store: CuratorRulesStore
    private let url: URL
    private var timer: DispatchSourceTimer?
    private var lastMTime: Date?

    init?(store: CuratorRulesStore, url: URL?) {
        guard let url else { return nil }
        self.store = store
        self.url = url
    }

    func start(interval: TimeInterval = 2.0) {
        let q = DispatchQueue(label: "curator.rules.reload.timer")
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let attrs = try? FileManager.default.attributesOfItem(atPath: self.url.path)
            let mtime = attrs?[.modificationDate] as? Date
            if self.lastMTime == nil { self.lastMTime = mtime }
            if let mtime, let last = self.lastMTime, mtime > last {
                let store = self.store
                Task.detached { _ = await store.reload() }
                self.lastMTime = mtime
            }
        }
        self.timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
