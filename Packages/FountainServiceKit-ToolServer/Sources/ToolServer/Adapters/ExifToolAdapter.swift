import Foundation

public struct ExifToolAdapter: ToolAdapter {
    private let base = ProcessAdapter(tool: "exiftool", executable: "/usr/bin/exiftool")
    public init() {}
    public var tool: String { base.tool }
    public func run(args: [String]) throws -> (Data, Int32) { try base.run(args: args) }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
