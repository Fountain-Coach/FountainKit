import Foundation
import PackagePlugin

@main
struct EnsureOpenAPIConfigPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let module = target as? SourceModuleTarget else {
            return []
        }

        let configFileNames = [
            "openapi-generator-config.yaml",
            "openapi-generator-config.yml"
        ]

        if configFileNames.contains(where: { module.hasConfiguration(named: $0) }) {
            return []
        }

        Diagnostics.error(
            "Missing OpenAPI generator configuration for target \(module.name). " +
            "Add one of \(configFileNames.joined(separator: ", ")) to \(module.directoryURL.path())."
        )

        throw PluginError.missingConfiguration(target: module.name)
    }
}

private enum PluginError: Error, CustomStringConvertible {
    case missingConfiguration(target: String)

    var description: String {
        switch self {
        case .missingConfiguration(let target):
            return "Missing OpenAPI generator configuration for target \(target)."
        }
    }
}

private extension SourceModuleTarget {
    func hasConfiguration(named fileName: String) -> Bool {
        let fileURL = directoryURL.appending(path: fileName, directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: fileURL.path())
    }
}
