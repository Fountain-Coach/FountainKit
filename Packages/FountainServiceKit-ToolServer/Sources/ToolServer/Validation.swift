import Foundation

public struct Validation {
    public enum Error: Swift.Error { case forbiddenArg(String) }
    public init() {}
    public func validate(args: [String]) throws {
        for arg in args {
            if arg.contains("..") { throw Error.forbiddenArg(arg) }
            if arg.starts(with: "/") && !SandboxPolicy.isPathAllowed(arg) {
                throw Error.forbiddenArg(arg)
            }
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
