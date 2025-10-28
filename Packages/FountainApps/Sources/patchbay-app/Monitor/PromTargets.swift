import Foundation

struct PromTarget {
    let job: String
    let port: Int
    let envPortKey: String
}

func defaultTargets() -> [PromTarget] {
    return [
        .init(job: "gateway", port: 8010, envPortKey: "GATEWAY_PORT"),
        .init(job: "planner", port: 8003, envPortKey: "PLANNER_PORT"),
        .init(job: "function-caller", port: 8004, envPortKey: "FUNCTION_CALLER_PORT"),
        .init(job: "persist", port: 8005, envPortKey: "PERSIST_PORT"),
        .init(job: "bootstrap", port: 8002, envPortKey: "BOOTSTRAP_PORT"),
        .init(job: "baseline-awareness", port: 8001, envPortKey: "BASELINE_AWARENESS_PORT"),
        .init(job: "tools-factory", port: 8011, envPortKey: "TOOLS_FACTORY_PORT"),
        .init(job: "tool-server", port: 8012, envPortKey: "TOOL_SERVER_PORT"),
        .init(job: "semantic-browser", port: 8007, envPortKey: "SEMANTIC_BROWSER_PORT"),
        .init(job: "patchbay", port: 7090, envPortKey: "PATCHBAY_PORT"),
    ]
}

func resolveURL(_ target: PromTarget) -> URL {
    let env = ProcessInfo.processInfo.environment
    let portStr = env[target.envPortKey]
    let port = Int(portStr ?? "") ?? target.port
    var comps = URLComponents()
    comps.scheme = env["PROMETHEUS_SCHEME"] ?? "http"
    comps.host = env["PROMETHEUS_HOST"] ?? "127.0.0.1"
    comps.port = port
    comps.path = "/metrics"
    return comps.url ?? URL(string: "http://127.0.0.1:\(port)/metrics")!
}

