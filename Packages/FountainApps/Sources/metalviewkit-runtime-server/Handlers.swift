import Foundation
import OpenAPIRuntime

final class MVKRuntimeHandlers: APIProtocol, @unchecked Sendable {
    // Minimal health implementation to get the server compiling; expand alongside handlers.
    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        let uptime = ProcessInfo.processInfo.systemUptime
        return .ok(.init(body: .json(.init(status: .ok, uptimeSec: uptime))))
    }

    // MIDI — inject UMP events (test producer)
    func injectMidiEvents(_ input: Operations.injectMidiEvents.Input) async throws -> Operations.injectMidiEvents.Output {
        guard case let .json(batch) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var frames: [[UInt32]] = []
        for ev in batch.events ?? [] {
            var words: [UInt32] = []
            if let p = ev.packet {
                if let w0 = p.w0 { words.append(w0) }
                if let w1 = p.w1 { words.append(w1) }
                if let w2 = p.w2 { words.append(w2) }
                if let w3 = p.w3 { words.append(w3) }
            }
            if !words.isEmpty { frames.append(words) }
        }
        _ = MVKBridge.sendBatch(frames)
        return .accepted(.init())
    }
}
