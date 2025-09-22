import Foundation

public struct FFmpegAdapter: ToolAdapter {
    private let base = ProcessAdapter(tool: "ffmpeg", executable: "/usr/bin/ffmpeg")
    public init() {}
    public var tool: String { base.tool }
    public func run(args: [String]) throws -> (Data, Int32) { try base.run(args: args) }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
