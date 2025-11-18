import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenAPICurator
import Yams

func loadDotEnv(path: String = ".env") {
    guard let data = try? String(contentsOfFile: path) else { return }
    for line in data.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { setenv(parts[0], parts[1], 1) }
    }
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

loadDotEnv()

var specPath: String?
var corpusId = ProcessInfo.processInfo.environment["DEFAULT_CORPUS_ID"] ?? "tools-factory"
var submit = false

let args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    let a = args[i]
    if a == "--spec", i + 1 < args.count {
        specPath = args[i + 1]
        i += 2
        continue
    }
    if a == "--corpus", i + 1 < args.count {
        corpusId = args[i + 1]
        i += 2
        continue
    }
    if a == "--submit" {
        submit = true
        i += 1
        continue
    }
    i += 1
}

guard let specPath else {
    if let data = "--spec path or url required\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    exit(2)
}

let specURL: URL
if let url = URL(string: specPath), url.scheme != nil {
    specURL = url
} else {
    specURL = URL(fileURLWithPath: specPath)
}

let specData: Data
if specURL.isFileURL {
    specData = (try? Data(contentsOf: specURL)) ?? Data()
} else {
    specData = (try? Data(contentsOf: specURL)) ?? Data()
}

let text = String(data: specData, encoding: .utf8) ?? ""
let operations = extractOperationIds(from: text)
let spec = Spec(operations: operations)
let result = OpenAPICuratorKit.run(specs: [spec])
let banned: Set<String> = ["metrics_metrics_get", "register_openapi", "list_tools"]
let filteredOps = result.spec.operations.filter { !banned.contains($0) }

let storageRoot = ProcessInfo.processInfo.environment["CURATOR_STORAGE_PATH"] ?? "/data/corpora"
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
       let tfURL = ProcessInfo.processInfo.environment["TOOLS_FACTORY_URL"],
       let token = ProcessInfo.processInfo.environment["TOOLS_FACTORY_TOKEN"],
       let url = URL(string: "\(tfURL)/tools/register?corpusId=\(corpusId)") {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-yaml", forHTTPHeaderField: "Content-Type")
        req.httpBody = yaml.data(using: .utf8)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
        sem.wait()
    }
}

var reportObj: [String: Any] = [
    "appliedRules": result.report.appliedRules,
    "collisions": result.report.collisions
]
if !diff.isEmpty {
    reportObj["diff"] = diff
}
if let reportDataOut = try? JSONSerialization.data(withJSONObject: reportObj, options: [.prettyPrinted]) {
    try? reportDataOut.write(to: reportOut)
}

print("Applied rules: \(result.report.appliedRules.count); Collisions: \(result.report.collisions.count)")
if !result.report.collisions.isEmpty {
    exit(1)
}
