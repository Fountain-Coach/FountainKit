import XCTest
@testable import EngraverChatCore
@testable import EngraverStudio

final class EngraverStudioSmokeTests: XCTestCase {
    @MainActor
    func testStudioRootInitializesWithDefaultConfig() throws {
        #if canImport(SwiftUI)
        if #available(macOS 13.0, *) {
            // Ensure configuration can be created from a minimal environment
            let env: [String: String] = [
                "FOUNTAIN_GATEWAY_URL": "http://127.0.0.1:8010"
            ]
            let config = EngraverStudioConfiguration(environment: env)
            _ = EngraverStudioRoot(configuration: config)
        }
        #endif
    }
}
