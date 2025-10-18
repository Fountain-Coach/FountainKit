import Foundation
import SwiftCursesKit
import FountainStoreClient

@main
struct EngravingCLI {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let corpus = env["ENGRAVING_CORPUS_ID"] ?? "engraving-lab"
        var app = EngravingApp(corpusId: corpus)
        _ = try? await app.run()
    }
}

struct EngravingApp: TerminalApp {
    var corpusId: String
    private var store: FountainStoreClient
    private var pages: [Page] = []
    private var selectedIndex: Int = 0
    private var message: String? = nil
    private var tickCount: Int = 0

    init(corpusId: String) {
        self.corpusId = corpusId
        self.store = EngravingApp.resolveStore()
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            let url: URL
            if dir.hasPrefix("~") {
                url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + String(dir.dropFirst()), isDirectory: true)
            } else {
                url = URL(fileURLWithPath: dir, isDirectory: true)
            }
            if let disk = try? DiskFountainStoreClient(rootDirectory: url) {
                return FountainStoreClient(client: disk)
            }
        }
        return FountainStoreClient(client: EmbeddedFountainStoreClient())
    }

    var banner: String { "Engraving TUI — \(corpusId)" }

    var body: some Scene {
        Screen {
            VStack(spacing: 1) {
                Title("Engraving — Corpus \(corpusId)")
                LogView(lines: listLines, maximumVisibleLines: 16)
                StatusBar(items: statusItems)
            }.padding(1)
        }
    }

    mutating func onEvent(_ event: Event, context: AppContext) async {
        switch event {
        case .tick:
            tickCount += 1
            if tickCount == 1 { await refresh() }
        case let .key(key):
            switch key {
            case let .character(c):
                await handleKey(c, context: context)
            }
        }
    }

    private mutating func handleKey(_ c: Character, context: AppContext) async {
        switch c {
        case "q":
            await context.quit()
        case "r":
            await refresh()
        case "j":
            moveSelection(delta: 1)
        case "k":
            moveSelection(delta: -1)
        default:
            break
        }
    }

    private mutating func refresh() async {
        do {
            let (total, list) = try await store.fetchPages(corpusId: corpusId, limit: 200, offset: 0)
            pages = list
            if selectedIndex >= pages.count { selectedIndex = max(0, pages.count - 1) }
            message = pages.isEmpty ? "No pages in corpus. Use fk engraving ingest-code or bootstrap." : "Loaded \(total) pages"
        } catch {
            message = "Load error: \(error.localizedDescription)"
        }
    }

    private mutating func moveSelection(delta: Int) {
        guard !pages.isEmpty else { return }
        selectedIndex = max(0, min(pages.count - 1, selectedIndex + delta))
    }

    private var listLines: [String] {
        var lines: [String] = []
        if pages.isEmpty {
            lines.append(message ?? "No pages")
        } else {
            lines.append("Pages:")
            for (i, p) in pages.enumerated() {
                let mark = (i == selectedIndex) ? ">" : " "
                lines.append(" \(mark) \(p.title) — \(p.host)")
            }
            lines.append("")
            if let p = pages[safe: selectedIndex] {
                lines.append("Selected: \(p.pageId)")
                lines.append(p.url)
            }
        }
        lines.append("")
        lines.append("Keys: j/k move • r refresh • q quit")
        return lines
    }

    private var statusItems: [StatusBar.Item] {
        [
            .label("q: quit"),
            .label("r: refresh"),
            .label("j/k: move")
        ]
    }
}

// Minimal mirror of Persist's Page
struct Page: Codable { let corpusId: String; let pageId: String; let url: String; let host: String; let title: String }

extension Array {
    subscript(safe index: Int) -> Element? {
        (indices).contains(index) ? self[index] : nil
    }
}

extension FountainStoreClient {
    func fetchPages(corpusId: String, limit: Int, offset: Int) async throws -> (Int, [Page]) {
        let resp = try await query(corpusId: corpusId, collection: "pages", query: Query(filters: ["corpusId": corpusId], limit: limit, offset: offset))
        let list = try resp.documents.map { try JSONDecoder().decode(Page.self, from: $0) }
        return (list.count, list)
    }
}
