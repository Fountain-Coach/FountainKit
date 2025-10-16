import Foundation
import FountainStoreClient
import ChatKitGatewayPlugin

/// Stores ChatKit attachment metadata in FountainStore.
public actor GatewayAttachmentStore: ChatKitAttachmentMetadataStore {
    private let store: FountainStoreClient
    private let corpusId: String
    private let collection: String
    private var ensuredCorpus = false

    public init(store: FountainStoreClient,
                corpusId: String = "chatkit",
                collection: String = "attachment-metadata") {
        self.store = store
        self.corpusId = corpusId
        self.collection = collection
    }

    public func upsert(metadata: ChatKitAttachmentMetadata) async throws {
        try await ensureCorpus()
        let record = AttachmentMetadataRecord(metadata: metadata)
        let payload = try JSONEncoder().encode(record)
        try await store.putDoc(corpusId: corpusId, collection: collection, id: metadata.attachmentId, body: payload)
    }

    public func metadata(for attachmentId: String) async throws -> ChatKitAttachmentMetadata? {
        try await ensureCorpus()
        guard let payload = try await store.getDoc(corpusId: corpusId, collection: collection, id: attachmentId) else {
            return nil
        }
        let record = try JSONDecoder().decode(AttachmentMetadataRecord.self, from: payload)
        return record.metadata
    }

    private func ensureCorpus() async throws {
        if ensuredCorpus { return }
        if try await store.getCorpus(corpusId) == nil {
            _ = try await store.createCorpus(corpusId, metadata: ["purpose": "chatkit-attachments", "collection": collection])
        }
        ensuredCorpus = true
    }

    private struct AttachmentMetadataRecord: Codable {
        let attachmentId: String
        let sessionId: String
        let threadId: String?
        let fileName: String
        let mimeType: String
        let sizeBytes: Int
        let checksum: String
        let storedAt: String

        init(metadata: ChatKitAttachmentMetadata) {
            self.attachmentId = metadata.attachmentId
            self.sessionId = metadata.sessionId
            self.threadId = metadata.threadId
            self.fileName = metadata.fileName
            self.mimeType = metadata.mimeType
            self.sizeBytes = metadata.sizeBytes
            self.checksum = metadata.checksum
            self.storedAt = metadata.storedAt
        }

        var metadata: ChatKitAttachmentMetadata {
            ChatKitAttachmentMetadata(attachmentId: attachmentId,
                                      sessionId: sessionId,
                                      threadId: threadId,
                                      fileName: fileName,
                                      mimeType: mimeType,
                                      sizeBytes: sizeBytes,
                                      checksum: checksum,
                                      storedAt: storedAt)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
