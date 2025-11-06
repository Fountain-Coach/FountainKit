import Foundation
import OpenAPIRuntime
import MetalViewKit

final class MVKRuntimeHandlers: APIProtocol, @unchecked Sendable {
    private var endpoints: [String: Components.Schemas.MidiEndpoint] = [:]
    // Minimal health implementation to get the server compiling; expand alongside handlers.
    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        let uptime = ProcessInfo.processInfo.systemUptime
        return .ok(.init(body: .json(.init(status: .ok, uptimeSec: uptime))))
    }

    // MIDI — inject UMP events (test producer)
    func injectMidiEvents(_ input: Operations.injectMidiEvents.Input) async throws -> Operations.injectMidiEvents.Output {
        guard case let .json(batch) = input.body else { return .undocumented(statusCode: 400, .init()) }
        var frames: [[UInt32]] = []
        for ev in batch.events {
            var words: [UInt32] = []
            let p = ev.packet
            words.append(UInt32(truncatingIfNeeded: p.w0))
            if let w1 = p.w1 { words.append(UInt32(truncatingIfNeeded: w1)) }
            if let w2 = p.w2 { words.append(UInt32(truncatingIfNeeded: w2)) }
            if let w3 = p.w3 { words.append(UInt32(truncatingIfNeeded: w3)) }
            if !words.isEmpty { frames.append(words) }
        }
        // Resolve target from query first, then fallback to env/default
        let q = input.query
        _ = MVKBridge.sendBatch(frames,
                                targetDisplayNameSubstring: q.targetDisplayName,
                                targetInstanceId: q.targetInstanceId)
        return .accepted(.init())
    }

    // GET /v1/midi/events — stubbed consumer for tests
    func readMidiEvents(_ input: Operations.readMidiEvents.Input) async throws -> Operations.readMidiEvents.Output {
        let out = Components.Schemas.MidiOutBatch(events: [])
        return .ok(.init(body: .json(out)))
    }

    // MIDI endpoints — in-memory runtime endpoints
    func listMidiEndpoints(_ input: Operations.listMidiEndpoints.Input) async throws -> Operations.listMidiEndpoints.Output {
        var list: [Components.Schemas.MidiEndpoint] = []
        // Include in-memory endpoints
        list.append(contentsOf: endpoints.values)
        // Reflect live MVK loopback instruments as input endpoints with id=instanceId
        let live = LoopbackMetalInstrumentTransport.shared.listDescriptors()
        for d in live {
            let create = Components.Schemas.MidiEndpointCreate(
                name: d.displayName,
                direction: .input,
                groups: 1,
                jrTimestampSupport: true
            )
            let ep = Components.Schemas.MidiEndpoint(value1: create, value2: .init(id: d.instanceId))
            // De-duplicate by id when both in-memory and live share the same id
            if !list.contains(where: { $0.value2.id == ep.value2.id }) {
                list.append(ep)
            }
        }
        return .ok(.init(body: .json(list)))
    }

    func createMidiEndpoint(_ input: Operations.createMidiEndpoint.Input) async throws -> Operations.createMidiEndpoint.Output {
        guard case let .json(body) = input.body else { return .undocumented(statusCode: 400, .init()) }
        let id = UUID().uuidString
        let ep = Components.Schemas.MidiEndpoint(
            value1: body,
            value2: .init(id: id)
        )
        endpoints[id] = ep
        return .created(.init(body: .json(ep)))
    }
}
