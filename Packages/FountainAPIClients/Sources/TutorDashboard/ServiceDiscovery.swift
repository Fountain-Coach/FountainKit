import Foundation
import Yams

public struct ServiceDescriptor: Sendable, Equatable {
    public let fileName: String
    public let title: String
    public let binaryName: String?
    public let port: Int
    public let servers: [URL]
    public let healthPaths: [String]
    public let capabilityPaths: [String]

    public init(
        fileName: String,
        title: String,
        binaryName: String?,
        port: Int,
        servers: [URL],
        healthPaths: [String],
        capabilityPaths: [String]
    ) {
        self.fileName = fileName
        self.title = title
        self.binaryName = binaryName
        self.port = port
        self.servers = servers
        self.healthPaths = healthPaths
        self.capabilityPaths = capabilityPaths
    }

    public func resolveBaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        for key in Self.environmentKeys(binaryName: binaryName, title: title) {
            if let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty,
               let url = URL(string: raw) {
                return url
            }
        }

        if let server = servers.first {
            return server
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        return components.url
    }

    private static func environmentKeys(binaryName: String?, title: String) -> [String] {
        var keys: [String] = []

        if let binaryName {
            let canonical = binaryName
                .uppercased()
                .map { $0.isLetter || $0.isNumber ? $0 : "_" }
                .reduce(into: "", { $0.append($1) })
                .replacingOccurrences(of: "__", with: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            if !canonical.isEmpty {
                keys.append("\(canonical)_URL")
            }
            if let aliases = knownEnvironmentAliases[binaryName.lowercased()] {
                keys.append(contentsOf: aliases)
            }
        }

        // Provide a final fallback based on the service title for contributors who
        // mirror documentation variable names verbatim.
        let titleKey = title
            .uppercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "", { $0.append($1) })
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if !titleKey.isEmpty {
            keys.append("\(titleKey)_URL")
        }

        return Array(LinkedHashSet(keys))
    }

    private static let knownEnvironmentAliases: [String: [String]] = [
        "baseline-awareness": ["AWARENESS_URL"],
        "persist": ["FOUNTAINSTORE_URL", "PERSIST_URL"],
        "planner": ["PLANNER_URL"],
        "function-caller": ["FUNCTION_CALLER_URL"],
        "tools-factory": ["TOOLS_FACTORY_URL"],
        "semantic-browser": ["SEMANTIC_BROWSER_URL"],
        "bootstrap": ["BOOTSTRAP_URL"],
        "gateway": ["FOUNTAIN_GATEWAY_URL"],
    ]
}

public struct ServiceDiscovery: Sendable {
    public let openAPIRoot: URL
    private let fileManager: FileManager

    public init(openAPIRoot: URL, fileManager: FileManager = .default) {
        self.openAPIRoot = openAPIRoot
        self.fileManager = fileManager
    }

    public func loadServices() throws -> [ServiceDescriptor] {
        let urls = try fileManager.contentsOfDirectory(at: openAPIRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "yml" || $0.pathExtension.lowercased() == "yaml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try urls.compactMap { url in
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            guard let root = try Yams.load(yaml: yamlString) as? [String: Any] else { return nil }
            let info = root["info"] as? [String: Any] ?? [:]
            let title = (info["title"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let binary = info["x-fountain.binary"] as? String

            guard let port = ServiceDiscovery.parsePort(info["x-fountain.port"]) else {
                return nil
            }

            let servers = (root["servers"] as? [[String: Any]] ?? []).compactMap { entry -> URL? in
                guard let raw = entry["url"] as? String else { return nil }
                return URL(string: raw)
            }

            let paths = root["paths"] as? [String: Any] ?? [:]
            let health = ServiceDiscovery.extractPaths(paths, containing: "health")
            let capabilities = ServiceDiscovery.extractPaths(paths, containing: "capabilities")

            return ServiceDescriptor(
                fileName: url.lastPathComponent,
                title: title,
                binaryName: binary,
                port: port,
                servers: servers,
                healthPaths: health,
                capabilityPaths: capabilities
            )
        }
    }

    private static func parsePort(_ value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let stringValue as String:
            return Int(stringValue)
        case let doubleValue as Double:
            return Int(doubleValue)
        default:
            return nil
        }
    }

    private static func extractPaths(_ paths: [String: Any], containing substring: String) -> [String] {
        let needle = substring.lowercased()
        return paths.keys
            .filter { $0.lowercased().contains(needle) }
            .sorted()
    }
}

private struct LinkedHashSet<Element: Hashable>: Sequence {
    private var ordered: [Element] = []
    private var seen: Set<Element> = []

    init(_ elements: [Element]) {
        for element in elements {
            if !seen.contains(element) {
                ordered.append(element)
                seen.insert(element)
            }
        }
    }

    func makeIterator() -> IndexingIterator<[Element]> {
        ordered.makeIterator()
    }
}
