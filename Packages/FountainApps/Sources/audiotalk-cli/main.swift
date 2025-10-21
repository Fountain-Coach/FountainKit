import Foundation
import ArgumentParser
import OpenAPIRuntime
import OpenAPIURLSession
import AudioTalkAPI

@main
struct AudioTalkCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
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

    struct Health: ParsableCommand {
        @OptionGroup var globals: GlobalOptions
        mutating func run() throws {
            Task {
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
            dispatchMain()
        }
    }

    struct Dictionary: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Dictionary operations", subcommands: [List.self, Upsert.self])
        struct List: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.listDictionary(.init())
                    guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                    let data = try enc.encode(body)
                    FileHandle.standardOutput.write(data)
                }
                dispatchMain()
            }
        }
        struct Upsert: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Option(name: .shortAndLong, help: "Token") var token: String
            @Option(name: .shortAndLong, help: "Value") var value: String
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let req = Components.Schemas.DictionaryUpsertRequest(items: [
                        .init(token: token, value: value, description: nil)
                    ])
                    let out = try await client.upsertDictionary(.init(body: .json(req)))
                    guard case .ok(let ok) = out, case .json(let resp) = ok.body else { print("{}"); Foundation.exit(2); return }
                    print(resp.updated)
                }
                dispatchMain()
            }
        }
    }

    struct Intent: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Intent operations", subcommands: [Parse.self, Apply.self])
        struct Parse: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument(help: "Phrase") var phrase: String
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let req = Components.Schemas.IntentRequest(phrase: phrase, context: nil)
                    let out = try await client.parseIntent(.init(body: .json(req)))
                    guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                    let data = try enc.encode(body)
                    FileHandle.standardOutput.write(data)
                }
                dispatchMain()
            }
        }
        struct Apply: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Option(name: .long, help: "If-Match ETag") var ifMatch: String?
            @Argument(help: "Notation session id") var session: String
            @Argument(help: "Token ops", parsing: .unconditionalRemaining) var tokens: [String]
            mutating func run() throws {
                Task {
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
                dispatchMain()
            }
        }
    }

    struct Notation: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Notation operations", subcommands: [NewSession.self, GetScore.self, PutScore.self])
        struct NewSession: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.createNotationSession(.init())
                    guard case .created(let c) = out, case .json(let sess) = c.body else { print("{}"); Foundation.exit(2); return }
                    print(sess.id)
                }
                dispatchMain()
            }
        }
        struct GetScore: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.getLilySource(.init(path: .init(id: id)))
                    guard case .ok(let ok) = out, case .plainText(let body) = ok.body else { print(""); Foundation.exit(2); return }
                    let bytes = try await body.collect(upTo: 1<<20)
                    FileHandle.standardOutput.write(Data(bytes))
                }
                dispatchMain()
            }
        }
        struct PutScore: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            @Option(name: .long, help: "If-Match ETag") var ifMatch: String?
            @Argument(help: "Lily source text") var source: String
            mutating func run() throws {
                Task {
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
                dispatchMain()
            }
        }
    }

    struct Screenplay: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: ".fountain operations", subcommands: [NewSession.self, GetSource.self, PutSource.self, Parse.self, MapCues.self, CueSheet.self])
        struct NewSession: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.createScreenplaySession(.init())
                    guard case .created(let c) = out, case .json(let sess) = c.body else { print("{}"); Foundation.exit(2); return }
                    print(sess.id)
                }
                dispatchMain()
            }
        }
        struct GetSource: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.getScreenplaySource(.init(path: .init(id: id)))
                    guard case .ok(let ok) = out, case .plainText(let body) = ok.body else { print(""); Foundation.exit(2); return }
                    let bytes = try await body.collect(upTo: 1<<20)
                    FileHandle.standardOutput.write(Data(bytes))
                }
                dispatchMain()
            }
        }
        struct PutSource: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            @Option(name: .long, help: "If-Match ETag") var ifMatch: String?
            @Argument(help: "Fountain source text") var source: String
            mutating func run() throws {
                Task {
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
                dispatchMain()
            }
        }
        struct Parse: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.parseScreenplay(.init(path: .init(id: id)))
                    guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                    let data = try enc.encode(body)
                    FileHandle.standardOutput.write(data)
                }
                dispatchMain()
            }
        }
        struct MapCues: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument var id: String
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.mapScreenplayCues(.init(path: .init(id: id), body: .json(.init(theme_table: nil, hints: nil))))
                    guard case .ok(let ok) = out else { print("{}"); Foundation.exit(2); return }
                    switch ok.body {
                    case .json(let payload):
                        print(payload.cues?.count ?? 0)
                    }
                }
                dispatchMain()
            }
        }
        struct CueSheet: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Option(name: .long, help: "Format json|csv|pdf (default json)") var format: String?
            @Argument var id: String
            mutating func run() throws {
                Task {
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
                        let bytes = try await body.collect(upTo: 1<<20)
                        FileHandle.standardOutput.write(Data(bytes))
                    case .pdf(let body):
                        let bytes = try await body.collect(upTo: 1<<20)
                        FileHandle.standardOutput.write(Data(bytes))
                    }
                }
                dispatchMain()
            }
        }
    }

    struct Journal: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Journal ops", subcommands: [List.self])
        struct List: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            mutating func run() throws {
                Task {
                    let client = try AudioTalkCLI.makeClient(globals.baseURL)
                    let out = try await client.listJournal(.init())
                    guard case .ok(let ok) = out, case .json(let body) = ok.body else { print("{}"); Foundation.exit(2); return }
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                    let data = try enc.encode(body)
                    FileHandle.standardOutput.write(data)
                }
                dispatchMain()
            }
        }
    }

    struct UMP: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "MIDI 2.0 UMP operations", subcommands: [Send.self])
        struct Send: ParsableCommand {
            @OptionGroup var globals: GlobalOptions
            @Argument(help: "Session ID") var session: String
            @Argument(help: "UMP hex packets", parsing: .unconditionalRemaining) var packets: [String]
            mutating func run() throws {
                Task {
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
                dispatchMain()
            }
        }
    }
}
