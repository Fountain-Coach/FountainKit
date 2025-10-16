import Foundation
import ChatKitGatewayPlugin
import FountainStoreClient

struct AttachmentCleanupJob: Sendable {
    private let uploadStore: ChatKitUploadStore
    private let metadataStore: any ChatKitAttachmentMetadataStore
    private let store: FountainStoreClient
    private let ttl: TimeInterval
    private let batchSize: Int
    private let corpusId: String
    private let collection: String
    private let clock: () -> Date
    private let decoder = JSONDecoder()

    init(uploadStore: ChatKitUploadStore,
         metadataStore: any ChatKitAttachmentMetadataStore,
         store: FountainStoreClient,
         ttl: TimeInterval,
         batchSize: Int = 100,
         corpusId: String = "chatkit",
         collection: String = "attachments",
         clock: @escaping () -> Date = Date.init) {
        self.uploadStore = uploadStore
        self.metadataStore = metadataStore
        self.store = store
        self.ttl = max(0, ttl)
        self.batchSize = max(1, batchSize)
        self.corpusId = corpusId
        self.collection = collection
        self.clock = clock
    }

    func runOnce() async {
        guard ttl > 0 else { return }
        let threshold = clock().addingTimeInterval(-ttl)
        var scanned = 0
        var deleted = 0
        var skipped = 0
        var errors: [String] = []

        do {
            var shouldContinue = true
            while shouldContinue {
                let query = Query(sort: [(field: "storedAt", ascending: true)], limit: batchSize)
                let response = try await store.query(corpusId: corpusId, collection: collection, query: query)
                if response.documents.isEmpty { break }

                var removedInBatch = false
                for document in response.documents {
                    scanned += 1
                    let record: AttachmentRecord
                    do {
                        record = try decoder.decode(AttachmentRecord.self, from: document)
                    } catch {
                        skipped += 1
                        errors.append("decode_error: \(error.localizedDescription)")
                        continue
                    }

                    guard let storedDate = Self.dateFormatter.date(from: record.storedAt) else {
                        skipped += 1
                        errors.append("invalid_timestamp: \(record.attachmentId)")
                        continue
                    }

                    if storedDate < threshold {
                        do {
                            try await uploadStore.delete(attachmentId: record.attachmentId)
                            try? await metadataStore.delete(attachmentId: record.attachmentId)
                            deleted += 1
                            removedInBatch = true
                        } catch {
                            errors.append("delete_failed: \(error.localizedDescription)")
                        }
                    } else {
                        shouldContinue = false
                        break
                    }
                }

                if !removedInBatch {
                    break
                }
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        await ChatKitLogging.recordCleanup(scanned: scanned,
                                           deleted: deleted,
                                           skipped: skipped,
                                           ttl: ttl,
                                           error: errors.isEmpty ? nil : errors.joined(separator: "; "))
    }

    @discardableResult
    func scheduleRecurring(every interval: TimeInterval) -> Task<Void, Never>? {
        guard interval > 0 else { return nil }
        return Task.detached { [ttl = ttl] in
            guard ttl > 0 else { return }
            while !Task.isCancelled {
                await self.runOnce()
                try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
            }
        }
    }

    private struct AttachmentRecord: Decodable {
        let attachmentId: String
        let storedAt: String
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
