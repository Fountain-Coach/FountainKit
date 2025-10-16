import Foundation
import ChatKitGatewayPlugin

enum ChatKitLogging {
    enum EventKind: String, Codable { case attachmentUploadSucceeded, attachmentUploadFailed, attachmentDownloadSucceeded, attachmentDownloadFailed, attachmentCleanup }

    struct Event: Codable, Sendable, Equatable {
        let timestamp: String
        let level: String
        let kind: EventKind
        let requestId: String?
        let attachmentId: String?
        let sessionId: String?
        let threadId: String?
        let fileName: String?
        let mimeType: String?
        let sizeBytes: Int?
        let status: Int?
        let code: String?
        let message: String?
        let bytes: Int?
        let deleted: Int?
        let scanned: Int?
        let skipped: Int?
        let ttlSeconds: Double?
    }

    typealias Sink = @Sendable (Event) -> Void

    private static let sinkActor = LogSinkActor(initial: ChatKitLogging.defaultSink)

    static func makeLogger() -> any ChatKitAttachmentLogger { StructuredLogger() }

    static func installSink(_ sink: @escaping Sink) async {
        await sinkActor.setSink(sink)
    }

    static func resetSink() async {
        await sinkActor.setSink(defaultSink)
    }

    static func capture<T>(_ operation: () async throws -> T) async rethrows -> ([Event], T) {
        let buffer = ChatKitLogBuffer()
        await installSink(buffer.sink())
        do {
            let result = try await operation()
            let events = buffer.snapshot()
            await resetSink()
            return (events, result)
        } catch {
            await resetSink()
            throw error
        }
    }

    static func recordCleanup(scanned: Int,
                              deleted: Int,
                              skipped: Int,
                              ttl: TimeInterval,
                              error: String?) async {
        let event = Event(timestamp: timestamp(),
                          level: error == nil ? "info" : "error",
                          kind: .attachmentCleanup,
                          requestId: nil,
                          attachmentId: nil,
                          sessionId: nil,
                          threadId: nil,
                          fileName: nil,
                          mimeType: nil,
                          sizeBytes: nil,
                          status: nil,
                          code: nil,
                          message: error,
                          bytes: nil,
                          deleted: deleted,
                          scanned: scanned,
                          skipped: skipped,
                          ttlSeconds: ttl)
        await emit(event)
    }

    static func emit(_ event: Event) async {
        await sinkActor.emit(event)
    }

    private static var defaultSink: Sink {
        { event in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(event), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        }
    }

    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private actor LogSinkActor {
    private var sink: ChatKitLogging.Sink

    init(initial: @escaping ChatKitLogging.Sink) {
        self.sink = initial
    }

    func setSink(_ sink: @escaping ChatKitLogging.Sink) {
        self.sink = sink
    }

    func emit(_ event: ChatKitLogging.Event) {
        sink(event)
    }
}

private struct StructuredLogger: ChatKitAttachmentLogger {
    func attachmentUploadSucceeded(requestId: String, metadata: ChatKitAttachmentMetadata) async {
        let event = ChatKitLogging.Event(timestamp: ChatKitLogging.timestamp(),
                                         level: "info",
                                         kind: .attachmentUploadSucceeded,
                                         requestId: requestId,
                                         attachmentId: metadata.attachmentId,
                                         sessionId: metadata.sessionId,
                                         threadId: metadata.threadId,
                                         fileName: metadata.fileName,
                                         mimeType: metadata.mimeType,
                                         sizeBytes: metadata.sizeBytes,
                                         status: 201,
                                         code: nil,
                                         message: nil,
                                         bytes: nil,
                                         deleted: nil,
                                         scanned: nil,
                                         skipped: nil,
                                         ttlSeconds: nil)
        await ChatKitLogging.emit(event)
    }

    func attachmentUploadFailed(requestId: String,
                                sessionId: String?,
                                threadId: String?,
                                attachmentId: String?,
                                fileName: String?,
                                mimeType: String?,
                                sizeBytes: Int?,
                                status: Int,
                                code: String,
                                message: String) async {
        let level = status >= 500 ? "error" : "warn"
        let event = ChatKitLogging.Event(timestamp: ChatKitLogging.timestamp(),
                                         level: level,
                                         kind: .attachmentUploadFailed,
                                         requestId: requestId,
                                         attachmentId: attachmentId,
                                         sessionId: sessionId,
                                         threadId: threadId,
                                         fileName: fileName,
                                         mimeType: mimeType,
                                         sizeBytes: sizeBytes,
                                         status: status,
                                         code: code,
                                         message: message,
                                         bytes: nil,
                                         deleted: nil,
                                         scanned: nil,
                                         skipped: nil,
                                         ttlSeconds: nil)
        await ChatKitLogging.emit(event)
    }

    func attachmentDownloadSucceeded(requestId: String,
                                     attachmentId: String,
                                     sessionId: String,
                                     bytes: Int) async {
        let event = ChatKitLogging.Event(timestamp: ChatKitLogging.timestamp(),
                                         level: "info",
                                         kind: .attachmentDownloadSucceeded,
                                         requestId: requestId,
                                         attachmentId: attachmentId,
                                         sessionId: sessionId,
                                         threadId: nil,
                                         fileName: nil,
                                         mimeType: nil,
                                         sizeBytes: nil,
                                         status: 200,
                                         code: nil,
                                         message: nil,
                                         bytes: bytes,
                                         deleted: nil,
                                         scanned: nil,
                                         skipped: nil,
                                         ttlSeconds: nil)
        await ChatKitLogging.emit(event)
    }

    func attachmentDownloadFailed(requestId: String,
                                  attachmentId: String?,
                                  sessionId: String?,
                                  status: Int,
                                  code: String,
                                  message: String) async {
        let level = status >= 500 ? "error" : "warn"
        let event = ChatKitLogging.Event(timestamp: ChatKitLogging.timestamp(),
                                         level: level,
                                         kind: .attachmentDownloadFailed,
                                         requestId: requestId,
                                         attachmentId: attachmentId,
                                         sessionId: sessionId,
                                         threadId: nil,
                                         fileName: nil,
                                         mimeType: nil,
                                         sizeBytes: nil,
                                         status: status,
                                         code: code,
                                         message: message,
                                         bytes: nil,
                                         deleted: nil,
                                         scanned: nil,
                                         skipped: nil,
                                         ttlSeconds: nil)
        await ChatKitLogging.emit(event)
    }
}

private final class ChatKitLogBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "chatkit.log.buffer")
    private var storage: [ChatKitLogging.Event] = []

    func sink() -> ChatKitLogging.Sink {
        { event in
            self.queue.sync { self.storage.append(event) }
        }
    }

    func snapshot() -> [ChatKitLogging.Event] {
        queue.sync { storage }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
