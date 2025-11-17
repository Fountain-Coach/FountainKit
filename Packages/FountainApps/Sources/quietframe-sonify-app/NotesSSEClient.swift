import Foundation

actor NotesSSEClient {
    static let shared = NotesSSEClient()
    private var running = false
    private var task: Task<Void, Never>? = nil
    private var lastCount = 0

    func start() {
        guard !running else { return }
        running = true
        task = Task(priority: .background) {
            while !Task.isCancelled {
                await self.fetchOnce()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            }
        }
    }

    func stop() {
        running = false
        task?.cancel()
        task = nil
    }

    private func fetchOnce() async {
        let url = URL(string: (ProcessInfo.processInfo.environment["MVK_RUNTIME_URL"] ?? "http://127.0.0.1:7777") + "/v1/midi/notes/stream")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            guard let s = String(data: data, encoding: .utf8) else { return }
            // Expect multiple lines starting with "data: ...\n\n"
            let lines = s.split(separator: "\n")
            for line in lines where line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let d = payload.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                    await render(arr)
                }
            }
        } catch {
            // ignore transient errors
        }
    }

    private func render(_ events: [[String: Any]]) async {
        if events.count == lastCount { return }
        lastCount = events.count
        let tail = events.suffix(8)
        for ev in tail {
            if let kind = ev["event"] as? String {
                switch kind {
                case "noteOn":
                    let n = ev["note"] as? Int ?? 0
                    let v = ev["velocity"] as? Int ?? 0
                    await MidiMonitorStore.shared.add("SSE NoteOn n=\(n) v=\(v)")
                case "noteOff":
                    let n = ev["note"] as? Int ?? 0
                    await MidiMonitorStore.shared.add("SSE NoteOff n=\(n)")
                case "cc":
                    let cc = ev["cc"] as? Int ?? 0
                    let val = ev["value"] as? Int ?? 0
                    await MidiMonitorStore.shared.add("SSE CC \(cc) = \(val)")
                case "pb":
                    let pb = ev["value14"] as? Int ?? 0
                    await MidiMonitorStore.shared.add("SSE PB v14=\(pb)")
                default:
                    break
                }
            }
        }
    }
}
