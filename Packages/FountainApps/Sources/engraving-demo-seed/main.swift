import Foundation
import FountainStoreClient
import LauncherSignature

@main
struct EngravingDemoSeed {
    static func main() async {
        verifyLauncherSignature()

        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "engraving-demo"
        let store = resolveStore()

        do {
            try await store.createCorpus(corpusId)
        } catch {
            // ignore if exists; Disk store will already have metadata
        }

        // Seed pages
        let pages: [Page] = [
            Page(corpusId: corpusId, pageId: "file:Hello.swift", url: "demo://Hello.swift", host: "demo", title: "Hello.swift"),
            Page(corpusId: corpusId, pageId: "file:Rules.swift", url: "demo://Rules.swift", host: "demo", title: "Rules.swift"),
            Page(corpusId: corpusId, pageId: "plan:starter", url: "store://plan/starter", host: "store", title: "Engraving Plan")
        ]

        for p in pages { _ = try? await store.addPage(p) }

        // Seed code segments
        let helloCode = """
        import Foundation

        struct Greeter {
            func greet(name: String) -> String {
                // TODO: localize greeting
                if name.isEmpty { fatalError("Name must not be empty") }
                return "Hello, \\(name)! This is a very long line used to demonstrate a style warning for line length that intentionally exceeds 120 characters so the demo corpus shows a mix of severities in the findings panel."
            }
        }
        """
        let rulesCode = """
        enum RuleEngine {
            static func isLongLine(_ s: String, limit: Int = 120) -> Bool { s.count > limit }
        }
        """
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "file:Hello.swift:code", pageId: "file:Hello.swift", kind: "code", text: helloCode))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "file:Rules.swift:code", pageId: "file:Rules.swift", kind: "code", text: rulesCode))
        _ = try? await store.addSegment(.init(corpusId: corpusId, segmentId: "plan:starter:notes", pageId: "plan:starter", kind: "notes", text: "- [ ] Explore corpus\n- [ ] Run Rules\n- [ ] Baseline & Diff"))

        // Seed entities (index)
        _ = try? await store.addEntity(.init(corpusId: corpusId, entityId: "entity:Greeter", name: "Greeter", type: "type"))
        _ = try? await store.addEntity(.init(corpusId: corpusId, entityId: "entity:greet", name: "greet(name:)", type: "function"))

        // Seed analysis summary
        _ = try? await store.addAnalysis(.init(corpusId: corpusId, analysisId: "analysis:hello-summary", pageId: "file:Hello.swift", summary: "Greeter.greet validates input and returns a greeting."))

        // Seed baseline (history)
        let baselineContent: [String: Any] = [
            "kind": "engraving-baseline",
            "pages": pages.map { $0.pageId },
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: baselineContent),
           let json = String(data: data, encoding: .utf8) {
            _ = try? await store.addBaseline(.init(corpusId: corpusId, baselineId: "baseline-initial", content: json))
        }

        // Seed reflection (reasoning)
        _ = try? await store.addReflection(.init(corpusId: corpusId, reflectionId: "reflect-1", question: "What should we improve next?", content: "Consider replacing fatalError with a typed error."))

        // Seed patterns (findings for Inspector)
        let findings: [[String: Any]] = [
            ["title": "TODO present", "severity": "info", "file": "Hello.swift", "line": 5],
            ["title": "fatalError used", "severity": "error", "file": "Hello.swift", "line": 6],
            ["title": "Long line (>120)", "severity": "warn", "file": "Hello.swift", "line": 7]
        ]
        let patternsPayload: [String: Any] = ["kind": "rules-findings", "findings": findings]
        if let pdata = try? JSONSerialization.data(withJSONObject: patternsPayload),
           let pjson = String(data: pdata, encoding: .utf8) {
            _ = try? await store.addPatterns(.init(corpusId: corpusId, patternsId: "rules-seeded", content: pjson))
        }

        // Seed a minimal chat transcript (context-first demo)
        let sessionId = UUID()
        let sessionName = "Demo Walkthrough"
        let startedAt = ISO8601DateFormatter().string(from: Date())
        func chatRecord(
            id: UUID, index: Int, createdAt: Date, prompt: String, answer: String, history: [[String: String]]
        ) -> [String: Any] {
            return [
                "recordId": id.uuidString,
                "corpusId": corpusId,
                "sessionId": sessionId.uuidString,
                "sessionName": sessionName,
                "sessionStartedAt": startedAt,
                "turnIndex": index,
                "createdAt": ISO8601DateFormatter().string(from: createdAt),
                "prompt": prompt,
                "answer": answer,
                "provider": "demo",
                "model": "demo",
                "usage": NSNull(),
                "raw": NSNull(),
                "functionCall": NSNull(),
                "tokens": [],
                "systemPrompts": [
                    "You are Engraver assistant. Keep context bundles attached to each answer."
                ],
                "history": history
            ]
        }
        let t0 = UUID()
        let r0 = chatRecord(
            id: t0,
            index: 0,
            createdAt: Date(),
            prompt: "Show me the Greeter code and point out issues.",
            answer: "Here is Greeter.greet from Hello.swift. I found a TODO, a fatalError, and an overly long line.",
            history: []
        )
        let t1 = UUID()
        let r1 = chatRecord(
            id: t1,
            index: 1,
            createdAt: Date().addingTimeInterval(2),
            prompt: "Create a baseline for this corpus.",
            answer: "I created baseline-initial; you can Diff to track drift.",
            history: [["role": "user", "content": "Show me the Greeter code and point out issues."],
                      ["role": "assistant", "content": "Here is Greeter.greet from Hello.swift. I found a TODO, a fatalError, and an overly long line."]]
        )
        for rec in [r0, r1] {
            if let data = try? JSONSerialization.data(withJSONObject: rec) {
                try? await store.putDoc(corpusId: corpusId, collection: "chat-turns", id: (rec["recordId"] as? String) ?? UUID().uuidString, body: data)
            }
        }

        // Attach explicit context to the first turn
        let attach0: [String: Any] = [
            "attachmentId": "attach:\(t0.uuidString)",
            "corpusId": corpusId,
            "recordId": t0.uuidString,
            "pages": ["file:Hello.swift"],
            "segments": ["file:Hello.swift:code"],
            "patterns": ["rules-seeded"],
            "entities": ["entity:Greeter", "entity:greet"],
            "notes": "Findings were derived from the code segment and stored as a patterns document."
        ]
        if let data = try? JSONSerialization.data(withJSONObject: attach0) {
            try? await store.putDoc(corpusId: corpusId, collection: "attachments", id: attach0["attachmentId"] as! String, body: data)
        }

        print("engraving-demo corpus seeded • corpusId=\(corpusId)")
        print("Tip: Run engraving-app with FOUNTAINSTORE_DIR set, then select the \"engraving-demo\" corpus.")
        print("     For the Arc sheet, run baseline-awareness-server against the same store.")
    }

    static func resolveStore() -> FountainStoreClient {
        let env = ProcessInfo.processInfo.environment
        let root = resolveStoreRoot(from: env)
        do {
            let disk = try DiskFountainStoreClient(rootDirectory: root)
            return FountainStoreClient(client: disk)
        } catch {
            FileHandle.standardError.write(Data("[engraving-demo-seed] WARN: falling back to in-memory store (\(error))\n".utf8))
            return FountainStoreClient(client: EmbeddedFountainStoreClient())
        }
    }

    static func resolveStoreRoot(from env: [String: String]) -> URL {
        if let override = env["FOUNTAINSTORE_DIR"], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded: String
            if override.hasPrefix("~") {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                expanded = home + String(override.dropFirst())
            } else {
                expanded = override
            }
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(".fountain/store", isDirectory: true)
    }
}
