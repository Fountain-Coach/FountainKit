import Foundation
import FountainRuntime
import OpenAPICurator
import Yams
import FountainStoreClient
import Crypto

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private let env = ProcessInfo.processInfo.environment
private let configStore = ConfigurationStore.fromEnvironment(env)
private let (curatorRulesStore, curatorRulesReloader): (CuratorRulesStore, CuratorRulesReloader?) = {
    let initialRules: Rules = loadCuratorRules(environment: env, store: configStore)
    let store = CuratorRulesStore(initialRules: initialRules, configURL: nil)
    var reloader: CuratorRulesReloader?
    if configStore == nil {
        let path = env["CURATOR_RULES_PATH"] ?? "Configuration/curator.yml"
        let url = URL(fileURLWithPath: path)
        reloader = CuratorRulesReloader(store: store, url: url)
        reloader?.start(interval: 2.0)
    }
    return (store, reloader)
}()

public func loadCuratorRules(environment: [String: String] = ProcessInfo.processInfo.environment,
                             store: ConfigurationStore? = nil) -> Rules {
    let svc = store ?? ConfigurationStore.fromEnvironment(environment)
    if let data = svc?.getSync("curator.yml"), let text = String(data: data, encoding: .utf8) {
        return parseRules(from: text)
    }
    let path = environment["CURATOR_RULES_PATH"] ?? "Configuration/curator.yml"
    let contents = (try? String(contentsOfFile: path)) ?? ""
    return parseRules(from: contents)
}

public func metrics_metrics_get() async -> HTTPResponse {
    let uptime = Int(ProcessInfo.processInfo.systemUptime)
    let counts = await curatorMetrics.snapshot()
    let rulesContents: String = { if let data = configStore?.getSync("curator.yml") { return String(data: data, encoding: .utf8) ?? "" } else { let path = env["CURATOR_RULES_PATH"] ?? "Configuration/curator.yml"; return (try? String(contentsOfFile: path)) ?? "" } }()
    let digest = SHA256.hash(data: Data(rulesContents.utf8))
    let rulesHash = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    var lines: [String] = []
    lines.append("openapi_curator_uptime_seconds \(uptime)")
    lines.append("curator_ops_total{action=\"kept\"} \(counts.kept)")
    lines.append("curator_ops_total{action=\"removed\"} \(counts.removed)")
    lines.append("curator_ops_total{action=\"renamed\"} \(counts.renamed)")
    lines.append("curator_collisions_total \(counts.collisions)")
    lines.append("curator_submit_total{status=\"success\"} \(counts.submitSuccess)")
    lines.append("curator_submit_total{status=\"error\"} \(counts.submitError)")
    lines.append("curator_rules_version \(rulesHash)")
    let body = Data(lines.joined(separator: "\n").utf8)
    return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
}

func extractOperationIds(from text: String) -> [String] {
    var ops: [String] = []
    for line in text.split(separator: "\n") {
        if let range = line.range(of: "operationId:") {
            let op = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !op.isEmpty { ops.append(String(op)) }
        }
    }
    return ops
}

func queryParams(from path: String) -> [String: String] {
    guard let qIndex = path.firstIndex(of: "?") else { return [:] }
    let query = path[path.index(after: qIndex)...]
    var out: [String: String] = [:]
    for pair in query.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { out[parts[0]] = parts[1] }
    }
    return out
}

public func makeOpenAPICuratorKernel() -> HTTPKernel {
    HTTPKernel { req in
        let env = ProcessInfo.processInfo.environment
        let pathOnly = req.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? req.path
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: true)
        do {
            switch (req.method, segments) {
            case ("POST", ["curate"]):
                let obj = try JSONSerialization.jsonObject(with: req.body) as? [String: Any] ?? [:]
                let corpusId = obj["corpusId"] as? String ?? env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
                let submit = (obj["submitToToolsFactory"] as? Bool) ?? false
                let toolsFactoryURL = env["TOOLS_FACTORY_URL"]
                let rawSpecs = obj["specs"] as? [Any] ?? []
                var specs: [Spec] = []
                for item in rawSpecs {
                    if let s = item as? String {
                        let url = URL(string: s).flatMap { $0.scheme != nil ? $0 : nil } ?? URL(fileURLWithPath: s)
                        let data = (try? Data(contentsOf: url)) ?? Data()
                        let text = String(data: data, encoding: .utf8) ?? ""
                        let ops = extractOperationIds(from: text)
                        specs.append(Spec(operations: ops))
                    } else if let dict = item as? [String: Any], let ops = dict["operations"] as? [String] {
                        specs.append(Spec(operations: ops))
                    }
                }
                let rules = await curatorRulesStore.rules
                let result = OpenAPICuratorKit.run(specs: specs, rules: rules)
                let banned: Set<String> = ["metrics_metrics_get", "register_openapi", "list_tools"]
                let filteredOps = result.spec.operations.filter { !banned.contains($0) }
                let totalInputOps = specs.reduce(0) { $0 + $1.operations.count }
                let removedOps = max(0, totalInputOps - filteredOps.count)
                let renameCount = result.report.appliedRules.count + result.report.collisions.count
                await curatorMetrics.recordCurate(kept: filteredOps.count, removed: removedOps, renamed: renameCount, collisions: result.report.collisions.count)

                let storageRoot = env["CURATOR_STORAGE_PATH"] ?? "/data/corpora"
                let ts = ISO8601DateFormatter().string(from: Date())
                let corpusDir = URL(fileURLWithPath: storageRoot).appendingPathComponent(corpusId)
                let outDir = corpusDir.appendingPathComponent(ts)
                try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                let specOut = outDir.appendingPathComponent("curated.yaml")
                let reportOut = outDir.appendingPathComponent("report.json")

                var diff: [String: [String]] = [:]
                let existing = (try? FileManager.default.contentsOfDirectory(atPath: corpusDir.path)) ?? []
                let previous = existing.filter { $0 < ts }.sorted().last
                if let prev = previous {
                    let prevFile = corpusDir.appendingPathComponent(prev).appendingPathComponent("curated.yaml")
                    if let prevText = try? String(contentsOf: prevFile),
                       let prevObj = try? Yams.load(yaml: prevText) as? [String: Any],
                       let prevOps = prevObj["operations"] as? [String] {
                        let prevSet = Set(prevOps)
                        let currSet = Set(filteredOps)
                        let added = Array(currSet.subtracting(prevSet)).sorted()
                        let removed = Array(prevSet.subtracting(currSet)).sorted()
                        if !added.isEmpty || !removed.isEmpty {
                            diff["added"] = added
                            diff["removed"] = removed
                        }
                    }
                }

                if let yaml = try? Yams.dump(object: ["operations": filteredOps]) {
                    try? yaml.write(to: specOut, atomically: true, encoding: .utf8)
                    if submit,
                       let tfURL = toolsFactoryURL,
                       let token = env["TOOLS_FACTORY_TOKEN"],
                       let url = URL(string: "\(tfURL)/tools/register?corpusId=\(corpusId)") {
                        var req = URLRequest(url: url)
                        req.httpMethod = "POST"
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        req.setValue("application/x-yaml", forHTTPHeaderField: "Content-Type")
                        req.httpBody = yaml.data(using: .utf8)
                        do {
                            let (_, resp) = try await URLSession.shared.data(for: req)
                            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                                await curatorMetrics.recordSubmit(success: true)
                            } else {
                                await curatorMetrics.recordSubmit(success: false)
                            }
                        } catch {
                            await curatorMetrics.recordSubmit(success: false)
                        }
                    }
                }

                var reportObj: [String: Any] = [
                    "appliedRules": result.report.appliedRules,
                    "collisions": result.report.collisions
                ]
                if !diff.isEmpty {
                    reportObj["diff"] = diff
                }
                if let reportData = try? JSONSerialization.data(withJSONObject: reportObj, options: [.prettyPrinted]) {
                    try? reportData.write(to: reportOut)
                }
                let respObj: [String: Any] = [
                    "curatedOpenAPI": ["operations": filteredOps],
                    "report": reportObj
                ]
                let json = try JSONSerialization.data(withJSONObject: respObj)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
            case ("POST", ["truth-table"]):
                let obj = try JSONSerialization.jsonObject(with: req.body) as? [String: Any] ?? [:]
                let rawSpecs = obj["specs"] as? [Any] ?? []
                var specs: [Spec] = []
                for item in rawSpecs {
                    if let s = item as? String {
                        let url = URL(string: s).flatMap { $0.scheme != nil ? $0 : nil } ?? URL(fileURLWithPath: s)
                        let data = (try? Data(contentsOf: url)) ?? Data()
                        let text = String(data: data, encoding: .utf8) ?? ""
                        let ops = extractOperationIds(from: text)
                        specs.append(Spec(operations: ops))
                    } else if let dict = item as? [String: Any], let ops = dict["operations"] as? [String] {
                        specs.append(Spec(operations: ops))
                    }
                }
                let rules = await curatorRulesStore.rules
                let result = OpenAPICuratorKit.run(specs: specs, rules: rules)
                let banned: Set<String> = ["metrics_metrics_get", "register_openapi", "list_tools"]
                let table = result.report.truthTable.filter { !banned.contains($0.key) }
                let json = try JSONEncoder().encode(table)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("POST", ["validate"]):
                let obj = try JSONSerialization.jsonObject(with: req.body) as? [String: Any] ?? [:]
                let rawSpecs = obj["specs"] as? [Any] ?? []
                var specs: [Spec] = []
                for item in rawSpecs {
                    if let s = item as? String {
                        let url = URL(string: s).flatMap { $0.scheme != nil ? $0 : nil } ?? URL(fileURLWithPath: s)
                        let data = (try? Data(contentsOf: url)) ?? Data()
                        let text = String(data: data, encoding: .utf8) ?? ""
                        let ops = extractOperationIds(from: text)
                        specs.append(Spec(operations: ops))
                    } else if let dict = item as? [String: Any], let ops = dict["operations"] as? [String] {
                        specs.append(Spec(operations: ops))
                    }
                }
                let rules = await curatorRulesStore.rules
                let result = OpenAPICuratorKit.run(specs: specs, rules: rules)
                let respObj: [String: Any] = [
                    "report": [
                        "appliedRules": result.report.appliedRules,
                        "collisions": result.report.collisions
                    ]
                ]
                let json = try JSONSerialization.data(withJSONObject: respObj)
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", ["rules"]):
                if let data = configStore?.getSync("curator.yml"),
                   let yamlObj = try? Yams.load(yaml: String(data: data, encoding: .utf8) ?? "") {
                    let json = try JSONSerialization.data(withJSONObject: yamlObj)
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
                }
                let path = env["CURATOR_RULES_PATH"] ?? "Configuration/curator.yml"
                if let contents = try? String(contentsOfFile: path),
                   let yamlObj = try? Yams.load(yaml: contents) {
                    let json = try JSONSerialization.data(withJSONObject: yamlObj)
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)
                }
                return HTTPResponse(status: 404)

            case ("PUT", ["rules"]):
                if let str = String(data: req.body, encoding: .utf8) {
                    let ok = await curatorRulesStore.replace(with: str)
                    return HTTPResponse(status: ok ? 204 : 400)
                }
                return HTTPResponse(status: 400)

            case ("GET", ["history"]):
                let qp = queryParams(from: req.path)
                let corpusId = qp["corpusId"] ?? env["DEFAULT_CORPUS_ID"] ?? "tools-factory"
                let storageRoot = env["CURATOR_STORAGE_PATH"] ?? "/data/corpora"
                let corpusDir = URL(fileURLWithPath: storageRoot).appendingPathComponent(corpusId)
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: corpusDir.path)) ?? []
                let json = try JSONSerialization.data(withJSONObject: ["snapshots": entries])
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", ["_health"]):
                let json = try JSONSerialization.data(withJSONObject: ["status": "ok"])
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: json)

            case ("GET", ["metrics"]):
                return await metrics_metrics_get()

            default:
                return HTTPResponse(status: 404)
            }
        } catch {
            return HTTPResponse(status: 400)
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
