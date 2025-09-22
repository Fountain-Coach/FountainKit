import Foundation
import Dispatch
import PublishingFrontend

/// CLI entry point launching ``PublishingFrontend``.
/// Loads configuration and starts the server on the main run loop.

let usage = "Usage: publishing-frontend\n"
let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
    if let data = usage.data(using: .utf8) { FileHandle.standardOutput.write(data) }
    exit(0)
}
if args.contains("--version") {
    if let data = "publishing-frontend 0.0.0\n".data(using: .utf8) { FileHandle.standardOutput.write(data) }
    exit(0)
}
if !args.isEmpty {
    if let data = usage.data(using: .utf8) { FileHandle.standardError.write(data) }
    exit(2)
}

let config = try loadPublishingConfig()
let app = PublishingFrontend(config: config)
Task { @MainActor in
    try await app.start()
}

dispatchMain()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
