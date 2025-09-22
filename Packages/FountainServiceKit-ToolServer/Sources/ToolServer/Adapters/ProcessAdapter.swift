import Foundation

public struct ProcessAdapter: ToolAdapter {
    public let tool: String
    let executable: String
    public init(tool: String, executable: String) {
        self.tool = tool
        self.executable = executable
    }
    public func run(args: [String]) throws -> (Data, Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (data, proc.terminationStatus)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
