import Foundation

public struct PDFExportMatrixAdapter: ToolAdapter {
    private let base = ProcessAdapter(tool: "pdf-export-matrix", executable: "/usr/bin/pdf-export-matrix")
    public init() {}
    public var tool: String { base.tool }
    public func run(args: [String]) throws -> (Data, Int32) { try base.run(args: args) }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
