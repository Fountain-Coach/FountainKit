import Foundation
import InstrumentNewCore

/// CLI entry point for `instrument-new`, delegating to `InstrumentNewCore`.
@main
struct InstrumentNewCLI {
    static func main() async {
        do {
            let cfg = try InstrumentNew.parseConfig()
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            try InstrumentNew.generate(in: root, config: cfg, dryRun: false)
        } catch {
            fputs("instrument-new error: \(error)\n", stderr)
            exit(1)
        }
    }
}

