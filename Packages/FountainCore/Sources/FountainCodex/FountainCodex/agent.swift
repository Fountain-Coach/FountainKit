import Foundation

/// Codex orchestration entry point describing how to build and test the project.
struct Agent {
    /// Entry point executed by the ``clientgen-service`` tool.
    /// Prints usage instructions for running the generators and tests.
    static func main() throws {
        print("""
        Codex Orchestration Steps:
        1. Run the generator:
           swift run clientgen-service --input OpenAPI/api.yaml --output Generated/
        2. Run tests:
           swift test -v
        3. Commit any changes under Generated/ and Sources/.
        """)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
