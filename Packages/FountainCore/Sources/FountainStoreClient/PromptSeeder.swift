import Foundation

/// Convenience helper to persist a Teatro prompt into FountainStore and print it.
/// Apps can call this during boot to keep prompts in sync and observable.
public enum PromptSeeder {
    /// Seeds the given prompt and optional facts into a corpus (page `prompt:<appId>`)
    /// using a disk store under `storeDir` (defaults to `$PWD/.fountain/store`).
    /// Prints the prompt to stdout.
    public static func seedAndPrint(
        appId: String,
        prompt: String,
        facts: [String: Any]? = nil,
        storeDir: URL? = nil
    ) async {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let root = storeDir ?? cwd.appendingPathComponent(".fountain/store", isDirectory: true)
        let client: FountainStoreClient
        if let disk = try? DiskFountainStoreClient(rootDirectory: root) {
            client = FountainStoreClient(client: disk)
        } else {
            client = FountainStoreClient(client: EmbeddedFountainStoreClient())
        }
        // Ensure corpus and write page/segments
        do { _ = try await client.createCorpus(appId) } catch { /* ignore if exists */ }
        let pageId = "prompt:\(appId)"
        let page = Page(corpusId: appId, pageId: pageId, url: "store://prompt/\(appId)", host: "store", title: "\(appId) — Teatro Prompt")
        _ = try? await client.addPage(page)
        _ = try? await client.addSegment(.init(corpusId: appId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: prompt))
        if let facts = facts,
           let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            _ = try? await client.addSegment(.init(corpusId: appId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: json))
        }
        // Print the prompt for observability
        print("\n=== Teatro Prompt (\(appId)) ===\n\(prompt)\n=== end prompt ===\n")
    }
}

