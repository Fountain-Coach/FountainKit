import Foundation

@main
struct ArcSpecCompilerCLI {
    static func main() throws {
        var specPath: String?
        var outputDir: String = "Packages/FountainSpecCuration/openapi/v1"

        var idx = 1
        let args = CommandLine.arguments
        while idx < args.count {
            let arg = args[idx]
            switch arg {
            case "--out":
                guard idx + 1 < args.count else {
                    throw CLIError.invalidArguments("--out requires a value")
                }
                outputDir = args[idx + 1]
                idx += 2
            case "-h", "--help":
                printUsage()
                return
            default:
                if specPath == nil {
                    specPath = arg
                } else {
                    throw CLIError.invalidArguments("Unexpected argument: \(arg)")
                }
                idx += 1
            }
        }

        guard let specPath else {
            printUsage()
            return
        }

        let compiler = ArcSpecCompiler()
        let specURL = URL(fileURLWithPath: specPath)
        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        let generated = try compiler.compile(specURL: specURL, outputDirectory: outputURL)
        print("Generated OpenAPI spec at \(generated.path)")
    }

    private static func printUsage() {
        print("""
        ArcSpec Compiler

        Usage:
          arcspec-compiler <path/to/spec.arc.yml> [--out <openapi-dir>]

        Options:
          --out <dir>   Directory where the OpenAPI YAML should be written (default: Packages/FountainSpecCuration/openapi/v1)
          -h, --help    Show this help message
        """)
    }

    enum CLIError: Error, CustomStringConvertible {
        case invalidArguments(String)

        var description: String {
            switch self {
            case .invalidArguments(let message):
                return message
            }
        }
    }
}
