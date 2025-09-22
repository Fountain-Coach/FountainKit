import Foundation

public struct ImageMagickAdapter: ToolAdapter {
    private let base = ProcessAdapter(tool: "imagemagick", executable: "/usr/bin/convert")
    public init() {}
    public var tool: String { base.tool }
    public func run(args: [String]) throws -> (Data, Int32) { try base.run(args: args) }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
