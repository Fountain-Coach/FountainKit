import Foundation
import SwiftCursesKit
import TutorDashboard

@main
struct TutorDashboardCLI {
    static func main() async {
        do {
            let rawArguments = Array(CommandLine.arguments.dropFirst())
            let options = try CommandLineOptions.parse(rawArguments)

            if options.showHelp {
                print(CommandLineOptions.helpText)
                return
            }

            let configuration = try DashboardConfiguration.load(options: options)

            if options.previewMode {
                let preview = TutorDashboardPreview(configuration: configuration)
                try await preview.render(width: options.previewWidth)
                return
            }

            let app = TutorDashboardApp(configuration: configuration)
            _ = try await app.run()
        } catch {
            let message = "TutorDashboard error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }
}

struct CommandLineOptions: Sendable {
    var showHelp: Bool = false
    var previewMode: Bool = false
    var previewWidth: Int = 100
    var openAPIRootOverride: String?
    var refreshIntervalOverride: Double?
    var environmentFileOverride: String?

    static let helpText: String = {
        """
        Usage: tutor-dashboard [options]

        Options:
          --help                   Show this help message and exit
          --preview                Render a headless snapshot of the service table and exit
          --preview-width=<cols>   Width to use for preview output (default: 100)
          --openapi-root=<path>    Override the OpenAPI directory used for service discovery
          --refresh-seconds=<n>    Override the automatic refresh cadence (seconds)
          --env-file=<path>        Load environment defaults from a specific dotenv file
        """
    }()

    static func parse(_ arguments: [String]) throws -> CommandLineOptions {
        var parsed = CommandLineOptions()

        for argument in arguments {
            if argument == "--help" || argument == "-h" {
                parsed.showHelp = true
            } else if argument == "--preview" {
                parsed.previewMode = true
            } else if let value = argument.value(forPrefix: "--preview-width=") {
                guard let width = Int(value), width > 0 else {
                    throw CommandLineError.invalidValue(argument)
                }
                parsed.previewWidth = max(40, width)
            } else if let value = argument.value(forPrefix: "--openapi-root=") {
                parsed.openAPIRootOverride = value
            } else if let value = argument.value(forPrefix: "--refresh-seconds=") {
                guard let seconds = Double(value), seconds > 0 else {
                    throw CommandLineError.invalidValue(argument)
                }
                parsed.refreshIntervalOverride = seconds
            } else if let value = argument.value(forPrefix: "--env-file=") {
                parsed.environmentFileOverride = value
            } else {
                throw CommandLineError.unknownArgument(argument)
            }
        }

        return parsed
    }
}

enum CommandLineError: Error, LocalizedError {
    case unknownArgument(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument)"
        case let .invalidValue(argument):
            return "Invalid value for argument: \(argument)"
        }
    }
}

private extension String {
    func value(forPrefix prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
