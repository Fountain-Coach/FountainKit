import Foundation

/// Resolves launcher-related resources (scripts, specs) relative to a FountainKit checkout.
struct LauncherResources {
    /// Default relative locations containing executable helper scripts.
    static let defaultScriptSearchPaths = [
        "Scripts"
    ]

    /// Default relative locations for the curated OpenAPI specifications.
    static let defaultSpecSearchPaths = [
        "Packages/FountainSpecCuration/openapi",
        "openapi"
    ]

    /// Environment key allowing callers to override where scripts are stored.
    static let scriptsOverrideKey = "FOUNTAINAI_SCRIPTS_DIR"

    /// Environment key allowing callers to override colon-separated spec directories.
    static let specsOverrideKey = "FOUNTAINAI_SPEC_PATHS"

    /// Validates that the provided URL points at a FountainKit checkout with scripts/specs present.
    /// - Parameters:
    ///   - url: Candidate repository root chosen by the user.
    ///   - environment: Environment variables that may override lookup behaviour.
    ///   - fileManager: File manager used for probing the filesystem.
    /// - Returns: `true` when required assets were discovered.
    static func isValidRepository(url: URL,
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  fileManager: FileManager = .default) -> Bool {
        let pkg = url.appendingPathComponent("Package.swift")
        guard fileManager.fileExists(atPath: pkg.path) else { return false }
        return locateSpecDirectory(repoRoot: url.path, environment: environment, fileManager: fileManager) != nil
            && locateScriptsDirectory(repoRoot: url.path, environment: environment, fileManager: fileManager) != nil
    }

    /// Finds the scripts directory for a checkout.
    static func locateScriptsDirectory(repoRoot: String,
                                       environment: [String: String] = ProcessInfo.processInfo.environment,
                                       fileManager: FileManager = .default) -> URL? {
        if let override = environment[scriptsOverrideKey], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true, relativeTo: URL(fileURLWithPath: repoRoot))
                .standardizedFileURL
            if directoryExists(at: url, fileManager: fileManager) { return url }
        }
        for candidate in defaultScriptSearchPaths {
            let url = URL(fileURLWithPath: candidate, isDirectory: true, relativeTo: URL(fileURLWithPath: repoRoot))
                .standardizedFileURL
            if directoryExists(at: url, fileManager: fileManager) { return url }
        }
        return nil
    }

    /// Finds the preferred OpenAPI spec directory for a checkout.
    static func locateSpecDirectory(repoRoot: String,
                                    environment: [String: String] = ProcessInfo.processInfo.environment,
                                    fileManager: FileManager = .default) -> URL? {
        var search: [String] = []
        if let override = environment[specsOverrideKey], !override.isEmpty {
            search.append(contentsOf: override.split(separator: ":").map(String.init))
        }
        search.append(contentsOf: defaultSpecSearchPaths)
        for candidate in search {
            let url = URL(fileURLWithPath: candidate, isDirectory: true, relativeTo: URL(fileURLWithPath: repoRoot))
                .standardizedFileURL
            if directoryExists(at: url, fileManager: fileManager) { return url }
        }
        return nil
    }

    /// Resolves a specific script inside the checkout.
    static func locateScript(named script: String,
                             repoRoot: String,
                             environment: [String: String] = ProcessInfo.processInfo.environment,
                             fileManager: FileManager = .default) -> URL? {
        guard let scripts = locateScriptsDirectory(repoRoot: repoRoot, environment: environment, fileManager: fileManager) else {
            return nil
        }
        let url = scripts.appendingPathComponent(script)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Convenience accessor for the launcher shell script.
    static func launcherScriptURL(repoRoot: String,
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  fileManager: FileManager = .default) -> URL? {
        locateScript(named: "launcher", repoRoot: repoRoot, environment: environment, fileManager: fileManager)
    }

    /// Convenience accessor for the diagnostics Swift script.
    static func diagnosticsScriptURL(repoRoot: String,
                                     environment: [String: String] = ProcessInfo.processInfo.environment,
                                     fileManager: FileManager = .default) -> URL? {
        locateScript(named: "start-diagnostics.swift", repoRoot: repoRoot, environment: environment, fileManager: fileManager)
    }

    private static func directoryExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }
}

// Convenience container for exposing the standard search paths in tests.
extension LauncherResources {
    static var defaultSpecPaths: [String] { defaultSpecSearchPaths }
    static var defaultScriptPaths: [String] { defaultScriptSearchPaths }
}

