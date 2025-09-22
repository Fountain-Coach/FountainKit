import Foundation

public struct LibPlistAdapter: ToolAdapter {
    private let base = ProcessAdapter(tool: "libplist", executable: "/usr/bin/plutil")
    public init() {}
    public var tool: String { base.tool }
    public func run(args: [String]) throws -> (Data, Int32) { try base.run(args: args) }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
