import Foundation
import SwiftUI
import AppKit
import EngraverStudio
import Security

@main
@available(macOS 13.0, *)
struct EngraverStudioStandaloneApp: App {
    private let configuration: EngraverStudioConfiguration

    init() {
        var env = ProcessInfo.processInfo.environment
        if CommandLine.arguments.contains("--debug") {
            env["ENGRAVER_DEBUG"] = "1"
        }
        // Allow folks to store secrets in the default macOS Keychain via `security add-generic-password`
        // without exposing them in plain text environment variables.
        if env["GATEWAY_BEARER"] == nil,
           let token = try? KeychainLookup.service("FountainAI", account: "GATEWAY_BEARER") {
            env["GATEWAY_BEARER"] = token
        }
        configuration = EngraverStudioConfiguration(environment: env)
    }

    var body: some Scene {
        WindowGroup {
            EngraverStudioRoot(configuration: configuration)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Lightweight Keychain helper

enum KeychainLookup {
    struct LookupError: Error {}

    static func service(_ service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw LookupError()
        }
        return value
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
