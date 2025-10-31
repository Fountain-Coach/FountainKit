import Foundation
import OpenAPIRuntime

// Generated protocol and types are made available by the OpenAPI generator in this module
// (APIProtocol, Operations, Components, registerHandlers(:)). Provide minimal handlers and a server bootstrap.

struct MIDIServiceHandlers: APIProtocol {
    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        let payload = Operations.getHealth.Output.Ok.Body.jsonPayload(status: .ok, uptimeSec: ProcessInfo.processInfo.systemUptime)
        return .ok(.init(body: .json(payload)))
    }

    func listTransports(_ input: Operations.listTransports.Input) async throws -> Operations.listTransports.Output {
        let payload = Operations.listTransports.Output.Ok.Body.jsonPayload(
            supported: [.midi2, .coremidi, .alsa, .loopback, .noop],
            _default: .midi2
        )
        return .ok(.init(body: .json(payload)))
    }

    func listDevices(_ input: Operations.listDevices.Input) async throws -> Operations.listDevices.Output { .ok(.init(body: .json([]))) }

    func listEndpoints(_ input: Operations.listEndpoints.Input) async throws -> Operations.listEndpoints.Output {
        let names = await SimpleMIDISender.listDestinationNames()
        let eps: [Components.Schemas.Endpoint] = names.map { n in
            .init(id: n, name: n, hasInput: false, hasOutput: true, transport: .coremidi)
        }
        return .ok(.init(body: .json(eps)))
    }

    func createEndpoint(_ input: Operations.createEndpoint.Input) async throws -> Operations.createEndpoint.Output {
        let name: String
        var hasInput = true
        var hasOutput = true
        var transport: Components.Schemas.TransportMode = .midi2
        switch input.body {
        case .json(let j):
            name = j.name
            hasInput = j.hasInput ?? true
            hasOutput = j.hasOutput ?? true
            transport = j.transport ?? .midi2
        }
        let ep = Components.Schemas.Endpoint(id: UUID().uuidString, name: name, hasInput: hasInput, hasOutput: hasOutput, transport: transport)
        return .created(.init(body: .json(ep)))
    }

    func deleteEndpoint(_ input: Operations.deleteEndpoint.Input) async throws -> Operations.deleteEndpoint.Output { .noContent }

    func sendUMP(_ input: Operations.sendUMP.Input) async throws -> Operations.sendUMP.Output {
        let words: [UInt32]
        let displayName: String?
        switch input.body {
        case .json(let j):
            words = j.words.map { UInt32($0) }
            displayName = j.target.displayName
        }
        do {
            try await SimpleMIDISender.send(words: words, toDisplayName: displayName)
            return .accepted
        } catch {
            return .accepted // keep accepted to avoid breaking clients; log in server
        }
    }
}

public enum MIDIServiceServer {
    public static func register(on transport: any ServerTransport) throws {
        try MIDIServiceHandlers().registerHandlers(on: transport, serverURL: URL(string: "/")!)
    }
}
