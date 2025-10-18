import Foundation
import PersistenceSeederKit

@main
struct PersistenceSeederCLI {
    static func main() async throws {
        var repoPath: String?
        var corpusId = "the-four-stars"
        var sourceRepo = "https://github.com/Fountain-Coach/the-four-stars"
        var outputDir = "./.fountain/seeding/the-four-stars"
        var analyzeOnly = false
        var summaryOnly = false
        var persistURLString: String?
        var persistAPIKey: String?
        var persistSecretRef: (service: String, account: String)?
        var uploadLimit: Int?
        var splitByPlay = false
        var corpusPrefixOverride: String?
        var corpusIdExplicit = false
        var playFilter: String?
        var nestedUnderCorpus: Bool = false

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
            case "--summary":
                summaryOnly = true
                idx += 1
            case "--corpus":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--corpus requires a value") }
                corpusId = args[idx + 1]
                corpusIdExplicit = true
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
            case "--persist-api-key-secret":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--persist-api-key-secret requires a value") }
                let token = args[idx + 1]
                guard let separator = token.firstIndex(of: ":") else {
                    throw CLIError.invalidArguments("--persist-api-key-secret expects service:account")
                }
                let service = String(token[..<separator])
                let account = String(token[token.index(after: separator)...])
                persistSecretRef = (service: service, account: account)
                idx += 2
            case "--upload-limit":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--upload-limit requires a numeric value") }
                guard let parsed = Int(args[idx + 1]), parsed > 0 else {
                    throw CLIError.invalidArguments("--upload-limit expects a positive integer")
                }
                uploadLimit = parsed
                idx += 2
            case "--split-by-play":
                splitByPlay = true
                idx += 1
            case "--corpus-prefix":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--corpus-prefix requires a value") }
                corpusPrefixOverride = args[idx + 1]
                idx += 2
            case "--play":
                guard idx + 1 < args.count else { throw CLIError.invalidArguments("--play requires a value") }
                playFilter = args[idx + 1]
                idx += 2
            case "--nested-under-corpus":
                // When set, seed into the specified corpus (via --corpus) but prefix pageId with the play slug.
                // This simulates nested corpora semantics without changing the corpusId path shape.
                nestedUnderCorpus = true
                idx += 1
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

        if splitByPlay && corpusIdExplicit && corpusPrefixOverride == nil {
            throw CLIError.invalidArguments("--corpus cannot be combined with --split-by-play; use --corpus-prefix to set a prefix")
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
                if splitByPlay {
                    let prefix = corpusPrefixOverride ?? corpusId
                    let results = try seeder.seedPlays(
                        repoPath: repoPath,
                        corpusPrefix: prefix,
                        sourceRepo: sourceRepo,
                        output: URL(fileURLWithPath: outputDir, isDirectory: true),
                        playFilter: playFilter
                    )
                    if summaryOnly {
                        let formatter = ManifestSummaryFormatter()
                        for play in results {
                            print(formatter.format(result: play.result, header: "\(play.title) [\(play.slug)]"))
                        }
                    } else {
                        let manifests = results.map { $0.result.manifest }
                        try printer.print(manifests)
                    }
                    if let persistURLString,
                       let baseURL = URL(string: persistURLString) {
                        if let secretRef = persistSecretRef, persistAPIKey == nil {
                            do {
                                persistAPIKey = try SecretLoader.load(service: secretRef.service, account: secretRef.account)
                            } catch {
                                fputs("ERROR: failed to load persist secret (\(error))\n", stderr)
                                exit(1)
                            }
                        }
                        let uploader = PersistUploader(baseURL: baseURL, apiKey: persistAPIKey)
                        for play in results {
                            do {
                                try await uploader.apply(
                                    manifest: play.result.manifest,
                                    speeches: play.result.speeches,
                                    uploadLimit: uploadLimit,
                                    hostOverride: play.slug,
                                    pagePrefix: nil
                                )
                            } catch {
                                fputs("UPLOAD ERROR [\(play.slug)]: \(error)\n", stderr)
                                exit(1)
                            }
                        }
                    }
                } else {
                    let result = try seeder.seed(
                        repoPath: repoPath,
                        corpusId: corpusId,
                        sourceRepo: sourceRepo,
                        output: URL(fileURLWithPath: outputDir, isDirectory: true),
                        playFilter: playFilter
                    )
                    if summaryOnly {
                        let formatter = ManifestSummaryFormatter()
                        print(formatter.format(result: result))
                    } else {
                        try printer.print(result.manifest)
                    }
                    if let persistURLString,
                       let baseURL = URL(string: persistURLString) {
                        if let secretRef = persistSecretRef, persistAPIKey == nil {
                            do {
                                persistAPIKey = try SecretLoader.load(service: secretRef.service, account: secretRef.account)
                            } catch {
                                fputs("ERROR: failed to load persist secret (\(error))\n", stderr)
                                exit(1)
                            }
                        }
                        let uploader = PersistUploader(baseURL: baseURL, apiKey: persistAPIKey)
                        do {
                            let pagePrefix: String?
                            if nestedUnderCorpus, let playFilter, !playFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let plays = try? FountainPlayParser().parseAllPlays(fileURL: URL(fileURLWithPath: repoPath))
                                pagePrefix = plays?.first { $0.title.localizedCaseInsensitiveContains(playFilter) || $0.slug.localizedCaseInsensitiveContains(playFilter) }?.slug ?? playFilter
                                    .lowercased()
                                    .replacingOccurrences(of: " ", with: "-")
                            } else {
                                pagePrefix = nil
                            }
                            try await uploader.apply(
                                manifest: result.manifest,
                                speeches: result.speeches,
                                uploadLimit: uploadLimit,
                                hostOverride: corpusId,
                                pagePrefix: pagePrefix
                            )
                        } catch {
                            fputs("UPLOAD ERROR: \(error)\n", stderr)
                            exit(1)
                        }
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
          --summary                Print a concise manifest summary instead of the full JSON.
          --persist-url <url>              Optional PersistService base URL; triggers ingestion when provided.
          --persist-api-key <key>          Optional API key attached as X-API-Key for PersistService.
          --persist-api-key-secret <ref>   Fetch API key from the local secret store; format service:account.
          --upload-limit <n>               Limit the number of derived speeches uploaded when --persist-url is set.
          --split-by-play                 Split the repository into one corpus per play.
          --corpus-prefix <prefix>        Custom prefix used when --split-by-play is enabled (default uses --corpus value).
          --play <title-or-slug>          Restrict seeding to a specific Shakespeare play.
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
