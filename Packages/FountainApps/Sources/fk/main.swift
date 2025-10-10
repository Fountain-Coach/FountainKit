import Foundation
import ArgumentParser
import Dispatch
// No launcher signature required for CLI

@main
struct FKCLI: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
        commandName: "fk",
        abstract: "FountainKit Ops CLI (spec-driven)",
        subcommands: [Status.self, Build.self, Up.self, Down.self, Logs.self]
        )
    }

    static func baseURL(_ override: String?) -> URL {
        URL(string: override ?? (ProcessInfo.processInfo.environment["FK_OPS_URL"] ?? "http://127.0.0.1:8020"))!
    }

    // Simple synchronous HTTP helper built on URLSession callbacks.
    static func http(_ req: URLRequest) throws -> (Data, URLResponse) {
        let sem = DispatchSemaphore(value: 0)
        var outData: Data? = nil
        var outResp: URLResponse? = nil
        var outErr: Error? = nil
        URLSession.shared.dataTask(with: req) { data, resp, err in
            outData = data; outResp = resp; outErr = err; sem.signal()
        }.resume()
        sem.wait()
        if let e = outErr { throw e }
        return (outData ?? Data(), outResp!)
    }

    struct Status: ParsableCommand {
        @Option(name: .shortAndLong, help: "FK Ops server base URL") var url: String?
        mutating func run() throws {
            let base = FKCLI.baseURL(url)
            var req = URLRequest(url: base.appendingPathComponent("/fk/status"))
            req.httpMethod = "GET"
            let (data, resp) = try FKCLI.http(req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ExitCode.failure }
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    struct Build: ParsableCommand {
        @Option(name: .shortAndLong, help: "FK Ops server base URL") var url: String?
        mutating func run() throws {
            let base = FKCLI.baseURL(url)
            var req = URLRequest(url: base.appendingPathComponent("/fk/build"))
            req.httpMethod = "POST"
            let (d, resp) = try FKCLI.http(req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ExitCode.failure }
            let ok = try JSONDecoder().decode(Ack.self, from: d)
            print(ok.message ?? "built")
        }
    }

    struct Up: ParsableCommand {
        @Option(name: .shortAndLong, help: "FK Ops server base URL") var url: String?
        mutating func run() throws {
            let base = FKCLI.baseURL(url)
            var req = URLRequest(url: base.appendingPathComponent("/fk/up"))
            req.httpMethod = "POST"
            let (d, resp) = try FKCLI.http(req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ExitCode.failure }
            let ok = try JSONDecoder().decode(Ack.self, from: d)
            print(ok.message ?? "up")
        }
    }

    struct Down: ParsableCommand {
        @Option(name: .shortAndLong, help: "FK Ops server base URL") var url: String?
        mutating func run() throws {
            let base = FKCLI.baseURL(url)
            var req = URLRequest(url: base.appendingPathComponent("/fk/down"))
            req.httpMethod = "POST"
            let (d, resp) = try FKCLI.http(req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ExitCode.failure }
            let ok = try JSONDecoder().decode(Ack.self, from: d)
            print(ok.message ?? "down")
        }
    }

    struct Logs: ParsableCommand {
        @Option(name: .shortAndLong, help: "FK Ops server base URL") var url: String?
        @Argument(help: "Service name (compose service or 'tool-server')") var service: String
        @Option(name: .shortAndLong, help: "Lines to tail") var lines: Int = 200
        mutating func run() throws {
            let base = FKCLI.baseURL(url)
            let svc = service; let ln = lines
            var comps = URLComponents(url: base.appendingPathComponent("/fk/logs"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "service", value: svc), URLQueryItem(name: "lines", value: String(ln))]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "GET"
            let (data, resp) = try FKCLI.http(req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ExitCode.failure }
            FileHandle.standardOutput.write(data)
        }
    }
}

// Minimal models matching the fk-ops spec
struct Ack: Codable { let ok: Bool; let message: String? }
