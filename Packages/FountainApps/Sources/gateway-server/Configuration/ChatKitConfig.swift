import Foundation

struct ChatKitConfig: Sendable {
    let maxAttachmentBytes: Int
    let allowedMimeTypes: Set<String>

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

    init(maxAttachmentBytes: Int = ChatKitConfig.defaultMaxAttachmentBytes,
         allowedMimeTypes: Set<String> = ChatKitConfig.defaultAllowedMimeTypes) {
        self.maxAttachmentBytes = max(0, maxAttachmentBytes)
        self.allowedMimeTypes = allowedMimeTypes.map { $0.lowercased() }.reduce(into: Set<String>()) { result, mime in
            let trimmed = mime.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result.insert(trimmed)
        }
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

    return ChatKitConfig(maxAttachmentBytes: maxBytes, allowedMimeTypes: allowed)
}
