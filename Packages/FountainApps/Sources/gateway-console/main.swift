import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import ApiClientsCore
import FountainDevHarness
import FountainAIKit

@main
struct GatewayConsole {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { printUsage(); exit(2) }
        switch cmd {
        case "recent":
            await recent()
        case "routes-reload":
            await routesReload()
        case "start":
            await start()
        case "stop":
            await stop()
        case "status":
            await status()
        case "rate-limit":
            await rateLimit(args: Array(args.dropFirst()))
        default:
            print("Unknown command: \(cmd)\n"); printUsage(); exit(2)
        }
    }

    static var baseURL: URL {
        if let s = ProcessInfo.processInfo.environment["FOUNTAIN_GATEWAY_URL"], let url = URL(string: s) { return url }
        return URL(string: "http://127.0.0.1:8010")!
    }

    static var bearer: String? {
        ProcessInfo.processInfo.environment["GATEWAY_BEARER"] ?? ProcessInfo.processInfo.environment["GATEWAY_JWT"]
    }

    static func recent() async {
        var url = baseURL
        url.append(path: "/admin/recent")
        var req = URLRequest(url: url)
        if let b = bearer, !b.isEmpty { req.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 200 {
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                fputs("error: status=\(http.statusCode)\n", stderr)
                exit(1)
            }
        } catch {
            fputs("recent error: \(error)\n", stderr); exit(1)
        }
    }

    static func routesReload() async {
        var url = baseURL
        url.append(path: "/admin/routes/reload")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let b = bearer, !b.isEmpty { req.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 204 { print("Routes reloaded.") } else { fputs("status=\(http.statusCode)\n", stderr); exit(1) }
        } catch {
            fputs("routes-reload error: \(error)\n", stderr); exit(1)
        }
    }

    static func start() async {
        let root = ProcessInfo.processInfo.environment["FOUNTAINKIT_ROOT"].flatMap { URL(fileURLWithPath: $0) }
        let env = EnvironmentControllerAdapter(fountainRepoRoot: root)
        await env.startEnvironment(includeExtras: true)
        await env.refreshStatus()
        print("Environment: \(env.overallState)")
    }

    static func stop() async {
        let root = ProcessInfo.processInfo.environment["FOUNTAINKIT_ROOT"].flatMap { URL(fileURLWithPath: $0) }
        let env = EnvironmentControllerAdapter(fountainRepoRoot: root)
        await env.stopEnvironment(includeExtras: true, force: true)
        print("Environment: stopped")
    }

    static func status() async {
        let root = ProcessInfo.processInfo.environment["FOUNTAINKIT_ROOT"].flatMap { URL(fileURLWithPath: $0) }
        let env = EnvironmentControllerAdapter(fountainRepoRoot: root)
        await env.refreshStatus()
        print("State: \(env.overallState)")
        for svc in env.services {
            print("- \(svc.name): \(svc.state.rawValue) :\(svc.port) \(svc.pid ?? "-")")
        }
    }

    static func rateLimit(args: [String]) async {
        // Example: gateway-console rate-limit --enabled false --limit 120 --restart
        var enabled: Bool? = nil
        var limit: Int? = nil
        var restart = false
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--enabled", i+1 < args.count { enabled = (args[i+1].lowercased() != "false"); i += 2; continue }
            if a == "--limit", i+1 < args.count { limit = Int(args[i+1]); i += 2; continue }
            if a == "--restart" { restart = true; i += 1; continue }
            i += 1
        }
        if let enabled { setenv("GATEWAY_DISABLE_RATELIMIT", enabled ? "0" : "1", 1) }
        if let limit { setenv("GATEWAY_RATE_LIMIT_PER_MINUTE", String(limit), 1) }
        if restart {
            await stop(); await start()
        } else {
            print("Rate limiter env applied. Restart to take effect.")
        }
    }

    static func printUsage() {
        print(
"""
gateway-console — minimal Gateway admin

USAGE:
  gateway-console recent                      # print recent requests JSON
  gateway-console routes-reload               # reload dynamic routes
  gateway-console start|stop|status           # manage dev environment (requires Scripts/*)
  gateway-console rate-limit --enabled <bool> [--limit <n>] [--restart]

ENV:
  FOUNTAIN_GATEWAY_URL   Base URL (default http://127.0.0.1:8010)
  GATEWAY_BEARER         Bearer token for admin
  FOUNTAINKIT_ROOT       Repo root for dev scripts (start/stop)
"""
        )
    }
}

