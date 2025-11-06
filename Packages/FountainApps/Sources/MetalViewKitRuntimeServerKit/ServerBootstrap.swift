import Foundation
import OpenAPIRuntime

public enum MetalViewKitRuntimeServer {
    static let sharedCore = MVKRuntimeCore()
    public static func register(on transport: any ServerTransport) throws {
        let handlers = MVKRuntimeHandlers(core: sharedCore)
        try handlers.registerHandlers(on: transport, serverURL: URL(string: "/")!)
    }

    /// JSON array string of current trace events used by WS/SSE providers.
    public static func tracingJSON() -> String {
        let enc = JSONEncoder()
        if let data = try? enc.encode(sharedCore.traces), let s = String(data: data, encoding: .utf8) { return s }
        return "[]"
    }

    /// JSON object string describing current audio backend status (backend.status event).
    public static func backendEventJSON() -> String {
        let s = sharedCore.audio
        let evt: [String: Any?] = [
            "type": "backend.status",
            "backend": s.backend.rawValue,
            "streaming": s.streaming,
            "deviceId": s.deviceId,
            "sampleRate": s.sampleRate,
            "blockFrames": s.blockFrames
        ]
        if let data = try? JSONSerialization.data(withJSONObject: evt.compactMapValues { $0 }), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
