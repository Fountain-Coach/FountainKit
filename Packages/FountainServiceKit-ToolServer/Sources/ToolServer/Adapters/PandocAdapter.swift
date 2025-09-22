import Foundation

public struct PandocAdapter: ToolAdapter {
    private let base = ProcessAdapter(tool: "pandoc", executable: "/usr/bin/pandoc")
    public init() {}
    public var tool: String { base.tool }
    public func run(args: [String]) throws -> (Data, Int32) { try base.run(args: args) }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
