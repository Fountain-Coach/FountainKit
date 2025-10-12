import Foundation

@main
struct ArcSpecCompilerCLI {
    static func main() throws {
        #if DEBUG
        let args = CommandLine.arguments
        #else
        let args = CommandLine.arguments
        #endif

        guard args.count >= 2 else {
            print("""
            ArcSpec Compiler (stub)

            Usage:
              arcspec-compiler <path/to/spec.arc.yml> [--out <openapi-dir>]

            This is a placeholder CLI. Future versions will parse the ArcSpec,
            emit OpenAPI documents, and invoke the Swift OpenAPI generator.
            """)
            return
        }

        let specPath = args[1]
        print("TODO: Compile ArcSpec at \(specPath)")
    }
}
