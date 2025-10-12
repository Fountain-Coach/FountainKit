import Foundation

@main
struct PersistenceSeederCLI {
    static func main() async throws {
        var repoPath: String?
        var corpusId = "the-four-stars"
        var sourceRepo = "https://github.com/Fountain-Coach/the-four-stars"
        var outputDir = "./.fountain/seeding/the-four-stars"
        var analyzeOnly = false
        var persistURLString: String?
        var persistAPIKey: String?

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
            case "--persist-url":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--persist-url requires a value") }
                persistURLString = args[idx + 1]
                idx += 2
            case "--persist-api-key":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--persist-api-key requires a value") }
                persistAPIKey = args[idx + 1]
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

        let printer = JSONPrinter()
        if analyzeOnly {
            let analyzer = RepositoryAnalyzer()
            do {
                let profile = try analyzer.analyze(repoPath: repoPath, maxSamples: 20)
                try printer.print(profile)
            } catch {
                fputs("ERROR: \(error)\n", stderr)
                exit(1)
            }
        } else {
            let seeder = PersistenceSeeder()
            do {
                let result = try seeder.seed(repoPath: repoPath, corpusId: corpusId, sourceRepo: sourceRepo, output: URL(fileURLWithPath: outputDir, isDirectory: true))
                try printer.print(result.manifest)
                if let persistURLString,
                   let baseURL = URL(string: persistURLString) {
                    let uploader = PersistUploader(baseURL: baseURL, apiKey: persistAPIKey)
                    do {
                        try await uploader.apply(manifest: result.manifest, speeches: result.speeches)
                    } catch {
                        fputs("UPLOAD ERROR: \(error)\n", stderr)
                        exit(1)
                    }
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
          --repo <path>            Local path to the cloned 'the-four-stars' repository.
          --analyze                Print a repository profile instead of generating the seed manifest.
          --corpus <id>            Target corpus ID (default: the-four-stars).
          --source <url>           Source repository URL for manifest metadata.
          --out <dir>              Output directory for seed-manifest.json (default: ./.fountain/seeding/the-four-stars).
          --persist-url <url>      Optional PersistService base URL; triggers ingestion when provided.
          --persist-api-key <key>  Optional API key attached as X-API-Key for PersistService.
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
