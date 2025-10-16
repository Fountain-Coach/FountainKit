import Foundation
import FountainStoreClient
import ChatKitGatewayPlugin

/// Persists ChatKit threads and assistant responses in FountainStore.
public actor GatewayThreadStore: ChatKitThreadStore {
    private let store: FountainStoreClient
    private let corpusId: String
    private let collection: String
    private var ensuredCorpus = false

    public init(store: FountainStoreClient,
                corpusId: String = "chatkit",
                collection: String = "threads") {
        self.store = store
        self.corpusId = corpusId
        self.collection = collection
    }

    public func createThread(session: ChatKitSessionStore.StoredSession,
                             title: String?,
                             metadata: [String: String]?) async throws -> ChatKitThread {
        var record = ThreadRecord.make(threadId: nil,
                                       session: session,
                                       title: title,
                                       metadata: metadata)
        try await persist(record)
        return record.model
    }

    public func ensureThread(session: ChatKitSessionStore.StoredSession,
                             requestedThreadId: String?,
                             metadata: [String: String]?) async throws -> ChatKitThread {
        if let requestedThreadId,
           let existing = try await load(threadId: requestedThreadId),
           existing.sessionId == session.id {
            return existing.model
        }
        var record = ThreadRecord.make(threadId: requestedThreadId,
                                       session: session,
                                       title: metadata?["title"],
                                       metadata: metadata)
        try await persist(record)
        return record.model
    }

    public func recordAssistantResponse(threadId: String,
                                         session: ChatKitSessionStore.StoredSession,
                                         responseId: String,
                                         answer: String,
                                         createdAt: String,
                                         toolCalls: [ChatKitToolCall]?,
                                         usage: [String: Double]?,
                                         metadata: [String: String]?) async throws -> ChatKitThread {
        guard var record = try await load(threadId: threadId), record.sessionId == session.id else {
            throw ChatKitThreadStoreError.threadNotFound
        }
        record.appendAssistantMessage(responseId: responseId,
                                      answer: answer,
                                      createdAt: createdAt,
                                      toolCalls: toolCalls,
                                      usage: usage)
        if let metadata, !metadata.isEmpty {
            record.mergeMetadata(metadata)
        }
        try await persist(record)
        return record.model
    }

    public func thread(threadId: String, sessionId: String) async throws -> ChatKitThread? {
        guard let record = try await load(threadId: threadId), record.sessionId == sessionId else {
            return nil
        }
        return record.model
    }

    public func listThreads(sessionId: String) async throws -> [ChatKitThreadSummary] {
        try await ensureCorpus()
        let query = Query(filters: ["sessionId": sessionId],
                          sort: [(field: "updatedAt", ascending: false)])
        let response = try await store.query(corpusId: corpusId, collection: collection, query: query)
        let decoder = JSONDecoder()
        return try response.documents
            .map { try decoder.decode(ThreadRecord.self, from: $0) }
            .filter { $0.sessionId == sessionId }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { $0.summary }
    }

    public func deleteThread(threadId: String, sessionId: String) async throws {
        guard let record = try await load(threadId: threadId), record.sessionId == sessionId else {
            throw ChatKitThreadStoreError.threadNotFound
        }
        try await ensureCorpus()
        try await store.deleteDoc(corpusId: corpusId, collection: collection, id: record.threadId)
    }

    // MARK: - Persistence helpers

    private func ensureCorpus() async throws {
        if ensuredCorpus { return }
        if try await store.getCorpus(corpusId) == nil {
            _ = try await store.createCorpus(corpusId,
                                             metadata: ["purpose": "chatkit-threads", "collection": collection])
        }
        ensuredCorpus = true
    }

    private func load(threadId: String) async throws -> ThreadRecord? {
        try await ensureCorpus()
        guard let data = try await store.getDoc(corpusId: corpusId, collection: collection, id: threadId) else {
            return nil
        }
        return try JSONDecoder().decode(ThreadRecord.self, from: data)
    }

    private func persist(_ record: ThreadRecord) async throws {
        try await ensureCorpus()
        let payload = try JSONEncoder().encode(record)
        try await store.putDoc(corpusId: corpusId, collection: collection, id: record.threadId, body: payload)
    }

    private struct ThreadRecord: Codable {
        var threadId: String
        var sessionId: String
        var title: String?
        var createdAt: String
        var updatedAt: String
        var metadata: [String: String]?
        var messages: [ChatKitThreadMessage]

        static func make(threadId: String?,
                         session: ChatKitSessionStore.StoredSession,
                         title: String?,
                         metadata: [String: String]?) -> ThreadRecord {
            let id = (threadId?.isEmpty == false ? threadId! : UUID().uuidString.lowercased())
            let timestamp = ThreadRecord.isoTimestamp()
            var meta = metadata ?? [:]
            if let title, !title.isEmpty {
                meta["title"] = title
            }
            return ThreadRecord(threadId: id,
                                sessionId: session.id,
                                title: meta["title"],
                                createdAt: timestamp,
                                updatedAt: timestamp,
                                metadata: meta.isEmpty ? nil : meta,
                                messages: [])
        }

        var model: ChatKitThread {
            ChatKitThread(thread_id: threadId,
                          session_id: sessionId,
                          title: title,
                          created_at: createdAt,
                          updated_at: updatedAt,
                          metadata: metadata,
                          messages: messages)
        }

        var summary: ChatKitThreadSummary {
            ChatKitThreadSummary(thread_id: threadId,
                                  session_id: sessionId,
                                  title: title,
                                  created_at: createdAt,
                                  updated_at: updatedAt,
                                  message_count: messages.count)
        }

        mutating func appendAssistantMessage(responseId: String,
                                              answer: String,
                                              createdAt: String,
                                              toolCalls: [ChatKitToolCall]?,
                                              usage: [String: Double]?) {
            let message = ChatKitThreadMessage(id: responseId,
                                               role: "assistant",
                                               content: answer,
                                               created_at: createdAt,
                                               attachments: nil,
                                               tool_calls: toolCalls,
                                               response_id: responseId,
                                               usage: usage)
            messages.append(message)
            updatedAt = createdAt
        }

        mutating func mergeMetadata(_ new: [String: String]) {
            var merged = metadata ?? [:]
            for (key, value) in new { merged[key] = value }
            metadata = merged.isEmpty ? nil : merged
            if let updatedTitle = merged["title"], !updatedTitle.isEmpty {
                title = updatedTitle
            }
        }

        private static func isoTimestamp(_ date: Date = Date()) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
