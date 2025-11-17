import Foundation
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
import FountainStoreClient

@main
struct ComposerStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ComposerRootView()
                .onAppear { if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) } }
                .task {
                    await ComposerStudioApp.printTeatroPromptIfAvailable()
                }
        }
    }
}

struct ComposerRootView: View {
    @StateObject private var scriptViewModel = ScriptViewModel()
    @State private var projectName: String = "Teatro Possibile"
    @State private var screenplay: String = ""

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.92)
                .ignoresSafeArea()
            HStack(alignment: .center, spacing: 48) {
                TeatroScorePane()
                    .frame(minWidth: 460, maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)

                TeatroScriptPane(
                    title: scriptTitle,
                    bodyText: scriptBody
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 72)
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onAppear { bootstrap() }
    }

    private var scriptTitle: String {
        scriptViewModel.sceneText
            .split(separator: "\n")
            .first.map(String.init) ?? "INT. OFFICE – DAY"
    }
    private var scriptBody: String {
        let lines = scriptViewModel.sceneText.split(separator: "\n")
        guard lines.count > 1 else { return scriptViewModel.sceneText }
        return lines.dropFirst().joined(separator: "\n")
    }

    // MARK: - Placeholder logic (fresh start)
    private func bootstrap() {
        // Keep screenplay text in sync with the script view model for later agent context.
        screenplay = scriptViewModel.sceneText
        if let name = UserDefaults.standard.string(forKey: "ComposerStudio.ProjectName"), !name.isEmpty {
            projectName = name
        }
    }
    private func saveDraft() {
        UserDefaults.standard.set(screenplay, forKey: "ComposerStudio.Screenplay")
        UserDefaults.standard.set(projectName, forKey: "ComposerStudio.ProjectName")
    }
}
@MainActor
extension ComposerStudioApp {
    static func printTeatroPromptIfAvailable() async {
        let store: FountainStoreClient
        let env = ProcessInfo.processInfo.environment

        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else {
                url = URL(fileURLWithPath: dir, isDirectory: true)
            }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                store = FountainStoreClient(client: disk)
            } else {
                store = FountainStoreClient(client: EmbeddedFountainStoreClient())
            }
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            if let disk = try? DiskFountainStoreClient(rootDirectory: cwd.appendingPathComponent(".fountain/store", isDirectory: true)) {
                store = FountainStoreClient(client: disk)
            } else {
                store = FountainStoreClient(client: EmbeddedFountainStoreClient())
            }
        }

        let corpusId = "composer-studio"
        let segmentId = "prompt:\(corpusId):teatro"

        do {
            if let data = try await store.getDoc(corpusId: corpusId, collection: "segments", id: segmentId),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                print("\n=== Teatro Prompt (\(corpusId)) ===\n\(text)\n=== end prompt ===\n")
            } else {
                FileHandle.standardError.write(Data("[composer-studio] Teatro prompt not found; run composer-studio-seed.\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("[composer-studio] error loading Teatro prompt: \(error)\n".utf8))
        }
    }
}
#else
@main
enum ComposerStudioUnavailable {
    static func main() { fputs("ComposerStudio requires macOS.\n", stderr) }
}
#endif
