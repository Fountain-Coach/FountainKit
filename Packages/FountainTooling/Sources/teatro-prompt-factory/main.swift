import Foundation

struct TeatroProperty: Codable {
    let name: String
    let type: String
    let min: Double?
    let max: Double?
    let `default`: Double?
}

struct TeatroTestsContract: Codable {
    let modulePath: String
    let suites: [String]
}

struct TeatroPromptContract: Codable {
    let appId: String
    let sceneTitle: String
    let role: String
    let host: String
    let surface: String
    let cores: [String]
    let properties: [TeatroProperty]
    let invariants: [String]
    let tests: TeatroTestsContract
    let agentId: String
    let specName: String
}

struct TeatroPromptBundle: Codable {
    let promptText: String
    let facts: [String: AnyCodable]
}

/// Lightweight type-erased wrapper for encoding dynamic JSON in facts.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) {
            value = v
        } else if let v = try? container.decode(Int.self) {
            value = v
        } else if let v = try? container.decode(Double.self) {
            value = v
        } else if let v = try? container.decode(String.self) {
            value = v
        } else if let v = try? container.decode([AnyCodable].self) {
            value = v.map { $0.value }
        } else if let v = try? container.decode([String: AnyCodable].self) {
            value = v.mapValues { $0.value }
        } else {
            value = ()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [Any]:
            try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

@main
struct TeatroPromptFactoryCLI {
    static func main() async {
        do {
            let args = CommandLine.arguments.dropFirst()
            guard let inputIndex = args.firstIndex(of: "--input"),
                  args.indices.contains(args.index(after: inputIndex)) else {
                fputs("Usage: teatro-prompt-factory --input <contract.json>\n", stderr)
                exit(1)
            }
            let path = String(args[args.index(after: inputIndex)])
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let contract = try JSONDecoder().decode(TeatroPromptContract.self, from: data)

            let promptText = renderPrompt(from: contract)
            let facts = renderFacts(from: contract)
            let bundle = TeatroPromptBundle(
                promptText: promptText,
                facts: facts.mapValues { AnyCodable($0) }
            )
            let out = try JSONEncoder().encode(bundle)
            FileHandle.standardOutput.write(out)
        } catch {
            fputs("teatro-prompt-factory error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func renderPrompt(from c: TeatroPromptContract) -> String {
        var lines: [String] = []
        // Scene + first paragraph (contract)
        lines.append("Scene: \(c.sceneTitle)")
        lines.append("")
        lines.append("Text:")
        lines.append("- Host: \(c.host).")
        lines.append("- Surface: \(c.surface).")
        if !c.cores.isEmpty {
            let joined = c.cores.joined(separator: ", ")
            lines.append("- Cores: \(joined).")
        }
        lines.append("")

        // Camera and Input
        lines.append("Camera and Input:")
        lines.append("- Transform core: honours shared camera math via Canvas2D (doc↔view) and related helpers.")
        lines.append("- Input behaviour is defined in tests and invariants for this scene; see Tests / Robot for details.")
        lines.append("")

        // Properties
        lines.append("Properties (PE / OpenAPI surface):")
        for p in c.properties {
            var desc = "- \(p.name) (\(p.type)"
            if let min = p.min { desc += ", min \(min)" }
            if let max = p.max { desc += ", max \(max)" }
            if let d = p.default { desc += ", default \(d)" }
            desc += ")"
            lines.append(desc)
        }
        lines.append("")

        // Invariants
        lines.append("Invariants:")
        for inv in c.invariants {
            lines.append("- \(inv)")
        }
        lines.append("")

        // Tests / Robot
        lines.append("Tests / Robot:")
        lines.append("- Module: \(c.tests.modulePath)")
        if !c.tests.suites.isEmpty {
            let suitesJoined = c.tests.suites.joined(separator: ", ")
            lines.append("- Suites: \(suitesJoined).")
        }
        lines.append("- Spec: \(c.specName) (agentId \(c.agentId)).")

        return lines.joined(separator: "\n")
    }

    private static func renderFacts(from c: TeatroPromptContract) -> [String: Any] {
        var props: [[String: Any]] = []
        for p in c.properties {
            var entry: [String: Any] = [
                "name": p.name,
                "type": p.type
            ]
            if let min = p.min { entry["min"] = min }
            if let max = p.max { entry["max"] = max }
            if let d = p.default { entry["default"] = d }
            props.append(entry)
        }
        return [
            "appId": c.appId,
            "agentId": c.agentId,
            "properties": props,
            "robot": [
                "subset": c.tests.suites,
                "invariants": c.invariants
            ],
            "spec": [
                "name": c.specName
            ]
        ]
    }
}
