import Foundation
import FountainStoreClient

@main
struct ConstellationStageSeedMain {
    static func main() async {
        let appId = "constellation-stage"

        // In a full pipeline this contract would likely live under Dist/ or
        // be provided via Tools Factory. For now we reuse the local JSON file.
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let contractURL = root.appendingPathComponent("constellation-stage.contract.json", isDirectory: false)

        guard FileManager.default.fileExists(atPath: contractURL.path) else {
            // Fallback: static prompt when contract is missing
            let prompt = """
            Scene: Constellation Stage — Isometric Family Field

            Text:
            - Host: SDLKit window on macOS; AppKit only via SDLKit internals.
            - Surface: Single isometric family field filling the window; no side panes or text editors; only representatives, field, and camera/replay controls are visible.

            Camera and Input:
            - Camera is under user control via mouse, trackpad, or MIDI; there is no automatic recentering or snapping.
            - The field uses Canvas2D/InfinityGraph math for transforms; pan and zoom are expressed as field.translation.* and field.zoom.

            Properties (PE / OpenAPI surface):
            - field.zoom (float)
            - field.translation.x (float)
            - field.translation.y (float)
            - field.replay.t (float)
            - field.replay.playing (bool)

            Invariants:
            - cameraUnderUserControl
            - noAutoRearrange
            - replayDeterministic
            - representativesStayOnField
            """
            await PromptSeeder.seedAndPrint(appId: appId, prompt: prompt, facts: nil)
            return
        }

        // Use teatro-prompt-factory to derive prompt and facts from the contract.
        // This keeps the prompt text and facts in sync with the shared template.
        if let bundle = generateBundle(fromContractAt: contractURL) {
            await PromptSeeder.seedAndPrint(appId: appId, prompt: bundle.prompt, facts: bundle.facts)
        } else {
            // If the factory is unavailable, fall back to a minimal prompt.
            let fallback = """
            Scene: Constellation Stage — Isometric Family Field

            Text:
            - Host: SDLKit window on macOS; AppKit only via SDLKit internals.
            - Surface: Single isometric family field; representatives and camera/replay controls only.
            """
            await PromptSeeder.seedAndPrint(appId: appId, prompt: fallback, facts: nil)
        }
    }

    private struct PromptBundle {
        let prompt: String
        let facts: [String: Any]
    }

    private static func generateBundle(fromContractAt url: URL) -> PromptBundle? {
        // For now we re-invoke the teatro-prompt-factory tool in-process by shelling out.
        // A future iteration could move the factory into a shared Swift library.
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = [
            "swift", "run",
            "--package-path", "Packages/FountainTooling",
            "-c", "debug",
            "teatro-prompt-factory",
            "--input", url.path
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let jsonData = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let prompt = obj["promptText"] as? String,
              let facts = obj["facts"] as? [String: Any] else {
            return nil
        }
        return PromptBundle(prompt: prompt, facts: facts)
    }
}
