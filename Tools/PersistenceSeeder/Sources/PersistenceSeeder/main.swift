import Foundation

@main
struct PersistenceSeederCLI {
    static func main() throws {
        var repoPath: String?
        var corpusId = "the-four-stars"
        var sourceRepo = "https://github.com/Fountain-Coach/the-four-stars"
        var outputDir = "./.fountain/seeding/the-four-stars"
        var analyzeOnly = false

        var idx = 1
        let args = CommandLine.arguments
        while idx < args.count {
            let arg = args[idx]
            switch arg {
            case "--repo":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--repo requires a value") }
                repoPath = args[idx + 1]
                idx += 2
            case "--analyze":
                analyzeOnly = true
                idx += 1
            case "--corpus":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--corpus requires a value") }
                corpusId = args[idx + 1]
                idx += 2
            case "--source":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--source requires a value") }
                sourceRepo = args[idx + 1]
                idx += 2
            case "--out":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--out requires a value") }
                outputDir = args[idx + 1]
                idx += 2
            case "-h", "--help":
                printUsage()
                return
            default:
                throw CLIError.invalidArguments("Unexpected argument: \(arg)")
            }
        }

        guard let repoPath else {
            printUsage()
            return
        }

        if analyzeOnly {
            let analyzer = RepositoryAnalyzer()
            do {
                let profile = try analyzer.analyze(repoPath: repoPath, maxSamples: 20)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(profile)
                if let string = String(data: data, encoding: .utf8) {
                    print(string)
                }
            } catch {
                fputs("ERROR: \(error)\n", stderr)
                exit(1)
            }
        } else {
            let seeder = PersistenceSeeder()
            do {
                let manifest = try seeder.seed(repoPath: repoPath, corpusId: corpusId, sourceRepo: sourceRepo, output: URL(fileURLWithPath: outputDir, isDirectory: true))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                encoder.dateEncodingStrategy = .iso8601
                let summaryData = try encoder.encode(manifest)
                if let string = String(data: summaryData, encoding: .utf8) {
                    print(string)
                }
            } catch {
                fputs("ERROR: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private static func printUsage() {
        print("""
        Persistence Seeder

        Usage:
          persistence-seeder --repo <path> [--analyze] [--corpus <id>] [--source <url>] [--out <dir>]

        Options:
          --repo <path>    Local path to the cloned 'the-four-stars' repository.
          --analyze        Print a repository profile instead of generating the seed manifest.
          --corpus <id>    Target corpus ID (default: the-four-stars).
          --source <url>   Source repository URL for manifest metadata.
          --out <dir>      Output directory for seed-manifest.json (default: ./.fountain/seeding/the-four-stars).
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
