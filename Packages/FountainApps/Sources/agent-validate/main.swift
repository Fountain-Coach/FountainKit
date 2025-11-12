import Foundation
import Yams
import Crypto

@main
struct AgentValidate {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        guard let path = args.first ?? ProcessInfo.processInfo.environment["AGENT_FILE"] else {
            fputs("usage: agent-validate <descriptor.(yaml|json)>\n", stderr)
            exit(2)
        }
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let obj: Any
            if path.hasSuffix(".yaml") || path.hasSuffix(".yml") {
                obj = try Yams.load(yaml: String(decoding: data, as: UTF8.self)) as Any
            } else {
                obj = try JSONSerialization.jsonObject(with: data)
            }
            guard let dict = obj as? [String: Any] else {
                throw NSError(domain: "agent-validate", code: 1, userInfo: [NSLocalizedDescriptionKey: "descriptor is not an object"])
            }
            try validate(dict)
            if let sig = try? signature(dict) {
                print("ok signature=\(sig)")
            } else {
                print("ok")
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func validate(_ d: [String: Any]) throws {
        // required string helpers
        func reqString(_ k: String) throws -> String {
            guard let s = d[k] as? String, !s.isEmpty else { throw err("missing or invalid \(k)") }
            return s
        }
        // x-agent-id
        let id = try reqString("x-agent-id")
        let idRe = try! NSRegularExpression(pattern: "^fountain\\.coach/agent/[a-z0-9._-]+/[a-z0-9._-]+$")
        guard idRe.firstMatch(in: id, range: NSRange(location: 0, length: id.utf16.count)) != nil else { throw err("invalid x-agent-id") }
        // kind
        let kind = try reqString("x-agent-kind")
        guard ["microservice","instrument","hybrid"].contains(kind) else { throw err("invalid x-agent-kind") }
        // version
        let ver = try reqString("x-agent-version")
        let semver = try! NSRegularExpression(pattern: "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$")
        guard semver.firstMatch(in: ver, range: NSRange(location: 0, length: ver.utf16.count)) != nil else { throw err("invalid x-agent-version") }
        // capabilities
        guard let caps = d["x-agent-capabilities"] as? [Any], !caps.isEmpty else { throw err("missing x-agent-capabilities") }
        let capRe = try! NSRegularExpression(pattern: "^[a-z][a-z0-9._-]*$")
        for c in caps {
            guard let s = c as? String, !s.isEmpty else { throw err("invalid capability item") }
            guard capRe.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) != nil else { throw err("invalid capability id: \(s)") }
        }
        // protocol(s)
        if let proto = d["x-agent-protocol"] as? String {
            guard ["openapi-3.1","midi-ci-pe","hybrid"].contains(proto) else { throw err("invalid x-agent-protocol") }
        } else if let protos = d["x-agent-protocols"] as? [String], !protos.isEmpty {
            guard Set(protos).isSubset(of: ["openapi-3.1","midi-ci-pe","hybrid"]) else { throw err("invalid x-agent-protocols") }
        } else {
            throw err("missing x-agent-protocol or x-agent-protocols")
        }
        // optional info block
        if let info = d["info"] as? [String: Any] {
            guard let title = info["title"] as? String, !title.isEmpty else { throw err("info.title required if info present") }
            guard let version = info["version"] as? String, !version.isEmpty else { throw err("info.version required if info present") }
            _ = title; _ = version
        }
    }

    static func signature(_ d: [String: Any]) throws -> String {
        // Canonicalize to stable JSON (sorted keys)
        let data = try canonicalJSON(d: d)
        return sha256Hex(data)
    }

    static func canonicalJSON(d: Any) throws -> Data {
        func sorted(_ any: Any) -> Any {
            if let dict = any as? [String: Any] {
                return Dictionary(uniqueKeysWithValues: dict.keys.sorted().map { ($0, sorted(dict[$0]!)) })
            } else if let arr = any as? [Any] {
                return arr.map(sorted(_:))
            }
            return any
        }
        let sortedObj = sorted(d)
        return try JSONSerialization.data(withJSONObject: sortedObj, options: [])
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = Crypto.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func err(_ msg: String) -> NSError { NSError(domain: "agent-validate", code: 2, userInfo: [NSLocalizedDescriptionKey: msg]) }
}
