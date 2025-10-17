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
