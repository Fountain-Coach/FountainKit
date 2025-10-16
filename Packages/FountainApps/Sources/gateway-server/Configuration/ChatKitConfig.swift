import Foundation

struct ChatKitConfig: Sendable {
    let maxAttachmentBytes: Int
    let allowedMimeTypes: Set<String>
    let attachmentTTL: TimeInterval
    let cleanupInterval: TimeInterval
    let cleanupBatchSize: Int

    static let defaultMaxAttachmentBytes = 25 * 1_048_576 // 25 MB
    static let defaultAllowedMimeTypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/webp",
        "image/gif",
        "application/pdf",
        "text/plain",
        "application/json",
        "application/octet-stream"
    ]

    static let defaultAttachmentTTL: TimeInterval = 24 * 60 * 60
    static let defaultCleanupInterval: TimeInterval = 15 * 60
    static let defaultCleanupBatchSize = 100

    init(maxAttachmentBytes: Int = ChatKitConfig.defaultMaxAttachmentBytes,
         allowedMimeTypes: Set<String> = ChatKitConfig.defaultAllowedMimeTypes,
         attachmentTTL: TimeInterval = ChatKitConfig.defaultAttachmentTTL,
         cleanupInterval: TimeInterval = ChatKitConfig.defaultCleanupInterval,
         cleanupBatchSize: Int = ChatKitConfig.defaultCleanupBatchSize) {
        self.maxAttachmentBytes = max(0, maxAttachmentBytes)
        self.allowedMimeTypes = allowedMimeTypes.map { $0.lowercased() }.reduce(into: Set<String>()) { result, mime in
            let trimmed = mime.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result.insert(trimmed)
        }
        self.attachmentTTL = max(0, attachmentTTL)
        self.cleanupInterval = max(0, cleanupInterval)
        self.cleanupBatchSize = max(1, cleanupBatchSize)
    }
}

func loadChatKitConfig(environment: [String: String] = ProcessInfo.processInfo.environment) -> ChatKitConfig {
    let maxBytes: Int
    if let rawMax = environment["CHATKIT_ATTACHMENT_MAX_MB"],
       let parsed = Double(rawMax), parsed > 0 {
        maxBytes = Int(parsed * 1_048_576.0)
    } else {
        maxBytes = ChatKitConfig.defaultMaxAttachmentBytes
    }

    let allowed: Set<String>
    if let rawList = environment["CHATKIT_ATTACHMENT_ALLOWED_MIME_TYPES"] {
        let components = rawList
            .split(whereSeparator: { ",".contains($0) || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        allowed = Set(components)
    } else {
        allowed = ChatKitConfig.defaultAllowedMimeTypes
    }

    let ttlSeconds: TimeInterval
    if let rawTTL = environment["CHATKIT_ATTACHMENT_TTL_HOURS"],
       let hours = Double(rawTTL), hours > 0 {
        ttlSeconds = hours * 3600.0
    } else {
        ttlSeconds = ChatKitConfig.defaultAttachmentTTL
    }

    let cleanupInterval: TimeInterval
    if let rawInterval = environment["CHATKIT_ATTACHMENT_CLEANUP_INTERVAL_MINUTES"],
       let minutes = Double(rawInterval), minutes > 0 {
        cleanupInterval = minutes * 60.0
    } else {
        cleanupInterval = ChatKitConfig.defaultCleanupInterval
    }

    let cleanupBatchSize: Int
    if let rawBatch = environment["CHATKIT_ATTACHMENT_CLEANUP_BATCH_SIZE"],
       let parsed = Int(rawBatch), parsed > 0 {
        cleanupBatchSize = parsed
    } else {
        cleanupBatchSize = ChatKitConfig.defaultCleanupBatchSize
    }

    return ChatKitConfig(maxAttachmentBytes: maxBytes,
                         allowedMimeTypes: allowed,
                         attachmentTTL: ttlSeconds,
                         cleanupInterval: cleanupInterval,
                         cleanupBatchSize: cleanupBatchSize)
}
