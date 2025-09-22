import Foundation

struct DashboardConfiguration: Sendable {
    let openAPIRoot: URL
    let environment: [String: String]
    let refreshIntervalTicks: Int

    static func load(options: CommandLineOptions, fileManager: FileManager = .default) throws -> DashboardConfiguration {
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let openAPIRoot = try resolveOpenAPIRoot(options: options, workingDirectory: workingDirectory, fileManager: fileManager)
        let environment = EnvironmentLoader.load(
            workingDirectory: workingDirectory,
            explicitFile: options.environmentFileOverride
        )
        let refreshSeconds = resolveRefreshInterval(options: options, environment: environment)
        let ticks = max(1, Int((refreshSeconds / 0.05).rounded(.toNearestOrAwayFromZero)))
        return DashboardConfiguration(openAPIRoot: openAPIRoot, environment: environment, refreshIntervalTicks: ticks)
    }

    private static func resolveOpenAPIRoot(
        options: CommandLineOptions,
        workingDirectory: URL,
        fileManager: FileManager
    ) throws -> URL {
        let overridePath = options.openAPIRootOverride
            ?? ProcessInfo.processInfo.environment["TUTOR_DASHBOARD_OPENAPI_ROOT"]

        let rootURL: URL
        if let overridePath, !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true, relativeTo: workingDirectory)
            rootURL = overrideURL.standardizedFileURL
        } else {
            rootURL = workingDirectory.appendingPathComponent("openapi/v1", isDirectory: true)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DashboardConfigurationError.missingOpenAPIDirectory(rootURL)
        }

        return rootURL
    }

    private static func resolveRefreshInterval(options: CommandLineOptions, environment: [String: String]) -> Double {
        if let override = options.refreshIntervalOverride {
            return max(1.0, override)
        }
        if let environmentValue = environment["TUTOR_DASHBOARD_REFRESH_SECONDS"],
           let value = Double(environmentValue), value > 0 {
            return value
        }
        return 5.0
    }
}

enum DashboardConfigurationError: Error, LocalizedError {
    case missingOpenAPIDirectory(URL)

    var errorDescription: String? {
        switch self {
        case let .missingOpenAPIDirectory(url):
            return "OpenAPI directory not found at \(url.path)"
        }
    }
}

enum EnvironmentLoader {
    static func load(workingDirectory: URL, explicitFile: String?) -> [String: String] {
        var defaults: [String: String] = [:]
        var visited: Set<URL> = []

        let environment = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default

        let candidates: [URL] = [
            explicitFile.map { URL(fileURLWithPath: $0, relativeTo: workingDirectory) },
            environment["TUTOR_DASHBOARD_ENV"].map { URL(fileURLWithPath: $0, relativeTo: workingDirectory) },
            workingDirectory.appendingPathComponent(".env", isDirectory: false),
            workingDirectory.appendingPathComponent(".env.example", isDirectory: false),
            workingDirectory.appendingPathComponent("Configuration/tutor-dashboard.env", isDirectory: false),
            workingDirectory.appendingPathComponent("Configuration/tutor-dashboard.env.example", isDirectory: false)
        ].compactMap { $0?.standardizedFileURL }

        for url in candidates where visited.insert(url).inserted {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = parseDotEnv(contents)
            defaults.merge(parsed) { current, _ in current }
        }

        return defaults.merging(environment) { current, override in override }
    }

    private static func parseDotEnv(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        contents.enumerateLines { rawLine, _ in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
            guard let separatorIndex = trimmed.firstIndex(of: "=") else { return }
            let keySlice = trimmed[..<separatorIndex].trimmingCharacters(in: .whitespaces)
            let valueSlice = trimmed[trimmed.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
            let stripped = stripQuotes(valueSlice)
            if !keySlice.isEmpty {
                values[String(keySlice)] = stripped
            }
        }
        return values
    }

    private static func stripQuotes(_ value: String) -> String {
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
