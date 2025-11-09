import Foundation
import OpenAPIRuntime
import MetalViewKit

// Generated protocol conformance lives here once generator runs.
enum QuietFrameStateProvider {
    static func snapshot() -> [String: Double] {
        // Minimal state exposure; expand as needed
        var s: [String: Double] = [:]
        s["engine.masterGain"] = 1.0
        return s
    }
}

// MARK: - Minimal server implementation scaffolding
extension Operations {
    struct Server: APIProtocol {
        func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output { .ok(.init(body: .json(.init(status: .ok)))) }

        func getState(_ input: Operations.getState.Input) async throws -> Operations.getState.Output { .ok(.init(body: .json(.init(additionalProperties: QuietFrameStateProvider.snapshot())))) }

        func postActSelect(_ input: Operations.postActSelect.Input) async throws -> Operations.postActSelect.Output {
            // Accept and no-op for now; UI wiring maps this in-app
            return .noContent(.init())
        }

        func postActParams(_ input: Operations.postActParams.Input) async throws -> Operations.postActParams.Output {
            return .noContent(.init())
        }

        func listMidiEndpoints(_ input: Operations.listMidiEndpoints.Input) async throws -> Operations.listMidiEndpoints.Output {
            // CoreMIDI is prohibited; return empty lists or later add RTP/BLE/Loopback discovery
            let srcs: [String] = []
            let dsts: [String] = []
            return .ok(.init(body: .json(.init(sources: srcs, destinations: dsts))))
        }

        func postMidiUMP(_ input: Operations.postMidiUMP.Input) async throws -> Operations.postMidiUMP.Output {
            guard case let .json(body) = input.body else { return .undocumented(statusCode: 400, .init()) }
            // Convert Int array to UInt32 safely (clamp to 0...UInt32.max)
            let words: [UInt32] = body.words.map { v in v < 0 ? 0 : (v > Int(UInt32.max) ? UInt32.max : UInt32(v)) }
            if let target = body.targetDisplayName, !target.isEmpty {
                _ = LoopbackMetalInstrumentTransport.shared.send(words: words, toDisplayName: target)
            } else {
                for desc in LoopbackMetalInstrumentTransport.shared.listDescriptors() {
                    _ = LoopbackMetalInstrumentTransport.shared.send(words: words, toInstanceId: desc.instanceId)
                }
            }
            return .noContent
        }
    }
}
