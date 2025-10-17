import Foundation
import SwiftUI
import AppKit
import EngraverStudio
import EngraverChatCore

@main
@available(macOS 13.0, *)
struct EngraverStudioStandaloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let configuration: EngraverStudioConfiguration

    init() {
        var env = ProcessInfo.processInfo.environment
        if CommandLine.arguments.contains("--debug") {
            env["ENGRAVER_DEBUG"] = "1"
        }
        // Resolve secrets via SecretStoreHelper (Keychain on macOS; libsecret on Linux)
        if env["GATEWAY_BEARER"] == nil,
           let token = SecretStoreHelper.read(service: "FountainAI", account: "GATEWAY_BEARER") {
            env["GATEWAY_BEARER"] = token
        }

        // Best-effort: infer FountainKit repo root if not set (enables auto environment management)
        if env["FOUNTAINKIT_ROOT"] == nil {
            if let inferred = Self.inferRepoRoot() {
                env["FOUNTAINKIT_ROOT"] = inferred.path
            }
        }
        configuration = EngraverStudioConfiguration(environment: env)
    }

    var body: some Scene {
        WindowGroup {
            EngraverStudioRoot(configuration: configuration)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }

    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        func applicationDidBecomeActive(_ notification: Notification) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

#if !canImport(SwiftUI) || !canImport(AppKit)
@main
enum EngraverStudioUnavailable {
    static func main() {
        fputs("Engraver Studio standalone app requires macOS 13 or newer.\n", stderr)
    }
}
#endif

// MARK: - Repo root inference

extension EngraverStudioStandaloneApp {
    private static func inferRepoRoot() -> URL? {
        // Walk up from current working directory to find a directory containing
        // both Package.swift and Scripts/.
        let fm = FileManager.default
        var url = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<6 { // walk up to 6 levels
            let package = url.appendingPathComponent("Package.swift")
            let scripts = url.appendingPathComponent("Scripts", isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: package.path), fm.fileExists(atPath: scripts.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }
}
