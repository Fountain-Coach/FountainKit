import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MIDI2Core
import MIDI2Transports
import MIDI2

public struct FlexReply: Codable, Equatable, Sendable {
    public var ack: Bool
    public var progress: Double?
    public var success: Bool?
    public var error: String?

    public init(ack: Bool, progress: Double? = nil, success: Bool? = nil, error: String? = nil) {
        self.ack = ack
        self.progress = progress
        self.success = success
        self.error = error
    }
}

public protocol FlexRouteHandler: Sendable {
    func handle(_ env: FlexEnvelope) async throws -> FlexReply
}

public final class HTTPRouteHandler: FlexRouteHandler {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func handle(_ env: FlexEnvelope) async throws -> FlexReply {
        let url = baseURL.appendingPathComponent(env.intent)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(env.body)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(FlexReply.self, from: data)
    }
}

public final class FlexBridge: @unchecked Sendable {
    private var transport: MIDITransport
    private let handler: FlexRouteHandler
    private var seenCorr: [String: UInt64] = [:]
    private let replayWindow: UInt64
    private let journalDirectory: URL

    public init(transport: MIDITransport, handler: FlexRouteHandler, journalDirectory: URL, replayWindow: UInt64 = 60_000) {
        self.transport = transport
        self.handler = handler
        self.journalDirectory = journalDirectory
        self.replayWindow = replayWindow
        self.transport.onReceiveUMP = { [weak self] words in
            Task { [weak self] in
                await self?.process(words: words)
            }
        }
    }

    func process(words: [UInt32]) async {
        guard let packet = Ump128(words: words) else { return }
        do {
            let env = try MIDI2Core.decode(packet)
            guard checkReplay(env: env) else {
                try send(reply: FlexReply(ack: false, error: "replay"), corr: env.corr)
                return
            }
            try journal(filename: "\(env.corr)-req.json", env)
            try send(reply: FlexReply(ack: true), corr: env.corr)
            let reply = try await handler.handle(env)
            try journal(filename: "\(env.corr)-res.json", reply)
            try send(reply: reply, corr: env.corr)
        } catch {
            try? send(reply: FlexReply(ack: false, error: error.localizedDescription), corr: "unknown")
        }
    }

    private func send(reply: FlexReply, corr: String) throws {
        var obj: [String: JSONValue] = ["ack": .bool(reply.ack)]
        if let p = reply.progress { obj["progress"] = .number(p) }
        if let s = reply.success { obj["success"] = .bool(s) }
        if let e = reply.error { obj["error"] = .string(e) }

        let env = FlexEnvelope(v: 1, ts: currentMillis(), corr: corr, intent: "flex.reply", body: .object(obj))
        let packet = try MIDI2Core.encode(env)
        try transport.send(umpWords: packet.words)
    }

    private func journal<T: Encodable>(filename: String, _ item: T) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let url = journalDirectory.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(item)
        try data.write(to: url)
    }

    private func checkReplay(env: FlexEnvelope) -> Bool {
        if let prev = seenCorr[env.corr], env.ts - prev < replayWindow { return false }
        seenCorr[env.corr] = env.ts
        return true
    }

    private func currentMillis() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
