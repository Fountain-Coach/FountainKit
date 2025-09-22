import Foundation

public struct SandboxPolicy {
    public static let allowedPaths: [String] = ["/tmp", "/var/tmp"]
    public static func isPathAllowed(_ path: String) -> Bool {
        return allowedPaths.contains { path.hasPrefix($0) }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
