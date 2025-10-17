import Foundation
import FountainAICore

// Minimal skeleton to unblock Phase 2.
// Re-expose core chat contracts so app targets can move to FountainAIKit.
public typealias ChatMessage = CoreChatMessage
public typealias ChatRequest = CoreChatRequest
public typealias ChatResponse = CoreChatResponse
public typealias ChatChunk = CoreChatChunk
public typealias ChatStreaming = CoreChatStreaming

public enum AIKitVersion {
    public static let current = "0.1.0"
}

