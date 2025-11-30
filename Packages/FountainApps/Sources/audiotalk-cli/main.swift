import Foundation
import ArgumentParser
import OpenAPIRuntime
import OpenAPIURLSession
import AudioTalkAPI

@main
struct AudioTalkCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audiotalk",
        abstract: "CLI for the AudioTalk service",
        subcommands: [Health.self, Dictionary.self, Intent.self, Notation.self, Screenplay.self, UMP.self]
    )

    struct GlobalOptions: ParsableArguments {
        @Option(name: .long, help: "Base URL, e.g., http://127.0.0.1:8080")
        var baseURL: String = "http://127.0.0.1:8080"
    }

    static func makeClient(_ base: String) throws -> AudioTalkAPI.Client {
        guard let url = URL(string: base) else { throw ValidationError("Invalid base URL: \(base)") }
        let transport = URLSessionTransport()
        return AudioTalkAPI.Client(serverURL: url, transport: transport)
    }

    struct Health: AsyncParsableCommand {
        @OptionGroup var globals: GlobalOptions
        mutating func run() async throws {
            let client = try AudioTalkCLI.makeClient(globals.baseURL)
            let out = try await client.getAudioTalkHealth(.init())
            switch out {
            case .ok(let ok):
                switch ok.body { case .json(let body): print("{\"ok\":\(body.ok)}") }
            default:
                fputs("unexpected response: \(out)\n", stderr)
                Foundation.exit(2)
            }
        }
    }

    struct Dictionary: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Dictionary operations", subcommands: [List.self, Upsert.self])
        struct List: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.listDictionary(.init())
                guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                let data = try enc.encode(body)
                FileHandle.standardOutput.write(data)
            }
        }
        struct Upsert: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Option(name: .shortAndLong, help: "Token") var token: String
            @Option(name: .shortAndLong, help: "Value") var value: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let req = Components.Schemas.DictionaryUpsertRequest(items: [
                    .init(token: token, value: value, description: nil)
                ])
                let out = try await client.upsertDictionary(.init(body: .json(req)))
                guard case .ok(let ok) = out, case .json(let resp) = ok.body else { print("{}"); Foundation.exit(2); return }
                print(resp.updated)
            }
        }
    }

    struct Intent: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Intent operations", subcommands: [Parse.self, Apply.self])
        struct Parse: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument(help: "Phrase") var phrase: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let req = Components.Schemas.IntentRequest(phrase: phrase, context: nil)
                let out = try await client.parseIntent(.init(body: .json(req)))
                guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                let data = try enc.encode(body)
                FileHandle.standardOutput.write(data)
            }
        }
        struct Apply: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Option(name: .long, help: "If-Match ETag") var ifMatch: String?
            @Argument(help: "Notation session id") var session: String
            @Argument(parsing: .captureForPassthrough, help: "Token ops") var tokens: [String]
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let ops = tokens.map { Components.Schemas.PlanOp(id: UUID().uuidString, kind: .token, value: $0, anchor: nil) }
                let plan = Components.Schemas.Plan(ops: ops, meta: .init(origin: .user, confidence: 1.0, source: "cli"))
                let req = Components.Schemas.ApplyPlanRequest(session_id: session, plan: plan)
                let input = Operations.applyPlan.Input(headers: .init(If_hyphen_Match: ifMatch), body: .json(req))
                let out = try await client.applyPlan(input)
                switch out {
                case .ok(let ok):
                    if let etag = ok.headers.ETag { print(etag) } else { print("") }
                case .conflict(let c):
                    if case .json(let body) = c.body { fputs("conflict: \(body.conflicts?.first?.code ?? "")\n", stderr) }
                    Foundation.exit(1)
                default:
                    fputs("unexpected: \(out)\n", stderr)
                    Foundation.exit(2)
                }
            }
        }
    }

    struct Notation: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Notation operations", subcommands: [NewSession.self, GetScore.self, PutScore.self])
        struct NewSession: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.createNotationSession(.init())
                guard case .created(let c) = out, case .json(let sess) = c.body else { print("{}"); Foundation.exit(2); return }
                print(sess.id)
            }
        }
        struct GetScore: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.getLilySource(.init(path: .init(id: id)))
                guard case .ok(let ok) = out, case .plainText(let body) = ok.body else { print(""); Foundation.exit(2); return }
                let bytes = try await [UInt8](collecting: body, upTo: 1<<20)
                FileHandle.standardOutput.write(Data(bytes))
            }
        }
        struct PutScore: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            @Option(name: .long, help: "If-Match ETag") var ifMatch: String?
            @Argument(help: "Lily source text") var source: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let input = Operations.putLilySource.Input(
                    path: .init(id: id),
                    headers: .init(If_hyphen_Match: ifMatch),
                    body: .plainText(HTTPBody(source))
                )
                let out = try await client.putLilySource(input)
                switch out {
                case .ok(let ok):
                    print(ok.headers.ETag ?? "")
                case .preconditionFailed:
                    fputs("412 precondition failed\n", stderr); Foundation.exit(1)
                default:
                    fputs("unexpected: \(out)\n", stderr); Foundation.exit(2)
                }
            }
        }
    }

    struct Screenplay: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: ".fountain operations", subcommands: [NewSession.self, GetSource.self, PutSource.self, Parse.self, MapCues.self, CueSheet.self, ApplyToNotation.self])
        struct NewSession: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.createScreenplaySession(.init())
                guard case .created(let c) = out, case .json(let sess) = c.body else { print("{}"); Foundation.exit(2); return }
                print(sess.id)
            }
        }
        struct GetSource: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.getScreenplaySource(.init(path: .init(id: id)))
                guard case .ok(let ok) = out, case .plainText(let body) = ok.body else { print(""); Foundation.exit(2); return }
                let bytes = try await [UInt8](collecting: body, upTo: 1<<20)
                FileHandle.standardOutput.write(Data(bytes))
            }
        }
        struct PutSource: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            @Option(name: .long, help: "If-Match ETag") var ifMatch: String?
            @Argument(help: "Fountain source text") var source: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let input = Operations.putScreenplaySource.Input(
                    path: .init(id: id),
                    headers: .init(If_hyphen_Match: ifMatch),
                    body: .plainText(HTTPBody(source))
                )
                let out = try await client.putScreenplaySource(input)
                switch out {
                case .ok(let ok):
                    print(ok.headers.ETag ?? "")
                case .preconditionFailed:
                    fputs("412 precondition failed\n", stderr); Foundation.exit(1)
                default:
                    fputs("unexpected: \(out)\n", stderr); Foundation.exit(2)
                }
            }
        }
        struct Parse: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.parseScreenplay(.init(path: .init(id: id)))
                guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                let data = try enc.encode(body)
                FileHandle.standardOutput.write(data)
            }
        }
        struct MapCues: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.mapScreenplayCues(.init(path: .init(id: id), body: .json(.init(theme_table: nil, hints: nil))))
                guard case .ok(let ok) = out else { print("{}"); Foundation.exit(2); return }
                switch ok.body {
                case .json(let payload):
                    print(payload.cues?.count ?? 0)
                }
            }
        }
        struct CueSheet: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Option(name: .long, help: "Format json|csv|pdf (default json)") var format: String?
            @Argument var id: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let qFmt: Operations.getCueSheet.Input.Query.formatPayload? = {
                    switch (format?.lowercased()) {
                    case .some("csv"): return .csv
                    case .some("pdf"): return .pdf
                    case .some("json"): return .json
                    default: return nil
                    }
                }()
                let input = Operations.getCueSheet.Input(path: .init(id: id), query: .init(format: qFmt))
                let out = try await client.getCueSheet(input)
                guard case .ok(let ok) = out else { print("{}"); Foundation.exit(2); return }
                switch ok.body {
                case .json(let body):
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                    let data = try enc.encode(body)
                    FileHandle.standardOutput.write(data)
                case .csv(let body):
                    let bytes = try await [UInt8](collecting: body, upTo: 1<<20)
                    FileHandle.standardOutput.write(Data(bytes))
                case .pdf(let body):
                    let bytes = try await [UInt8](collecting: body, upTo: 1<<20)
                    FileHandle.standardOutput.write(Data(bytes))
                }
            }
        }
        struct ApplyToNotation: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Option(name: .long, help: "If-Match ETag") var ifMatch: String?
            @Argument var screenplayId: String
            @Argument(help: "Notation session id") var session: String
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let body = Components.Schemas.ApplyCuesRequest(notation_session_id: session, options: nil)
                let input = Operations.applyScreenplayCuesToNotation.Input(
                    path: .init(id: screenplayId),
                    headers: .init(If_hyphen_Match: ifMatch),
                    body: .json(body)
                )
                let out = try await client.applyScreenplayCuesToNotation(input)
                switch out {
                case .ok(let ok):
                    if let etag = ok.headers.ETag { print(etag) } else { print("") }
                case .conflict(let c):
                    if case .json(let body) = c.body { fputs("conflict: \(body.conflicts?.first?.code ?? "")\n", stderr) }
                    Foundation.exit(1)
                case .notFound(let nf):
                    if case .json(let err) = nf.body { fputs("not found: \(err.code ?? err.error)\n", stderr) }
                    Foundation.exit(1)
                default:
                    fputs("unexpected: \(out)\n", stderr)
                    Foundation.exit(2)
                }
            }
        }
    }

    struct Journal: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Journal ops", subcommands: [List.self])
        struct List: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let out = try await client.listJournal(.init())
                guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                let data = try enc.encode(body)
                FileHandle.standardOutput.write(data)
            }
        }
    }

    struct UMP: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "MIDI 2.0 UMP operations", subcommands: [Send.self])
        struct Send: AsyncParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument(help: "Session ID") var session: String
            @Argument(parsing: .captureForPassthrough, help: "UMP hex packets") var packets: [String]
            mutating func run() async throws {
                let client = try AudioTalkCLI.makeClient(globals.baseURL)
                let items = packets.map { Components.Schemas.UMPBatch.itemsPayloadPayload(jr_timestamp: nil, host_time_ns: nil, ump: $0) }
                let req = Components.Schemas.UMPBatch(items: items)
                let out = try await client.sendUMPBatch(.init(path: .init(session: session), body: .json(req)))
                switch out {
                case .accepted:
                    print("accepted")
                case .badRequest(let b):
                    if case .json(let err) = b.body { fputs("bad request: \(err.error)\n", stderr) }
                    Foundation.exit(1)
                default:
                    fputs("unexpected: \(out)\n", stderr); Foundation.exit(2)
                }
            }
        }
    }
}
