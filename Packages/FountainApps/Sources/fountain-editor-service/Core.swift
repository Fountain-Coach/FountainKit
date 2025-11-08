import Foundation
import Teatro

// MARK: - Core helpers for the Fountain Editor service

struct FountainEditorCore {
    struct Scene { let index: Int; let title: String; let beats: [Beat] }
    struct Beat { let index: Int; let title: String }
    struct Act { let index: Int; let title: String; let scenes: [Scene] }
    struct Structure { let etag: String; let acts: [Act] }

    static func computeETag(for text: String) -> String {
        // Same simple FNV-1a 32-bit used in the UI model for determinism
        var hash: UInt32 = 0
        for b in text.utf8 { hash = (hash &* 16777619) ^ UInt32(b) }
        return String(format: "%08X", hash)
    }

    static func parseStructure(text: String) -> Structure {
        let parser = FountainParser()
        let nodes = parser.parse(text)
        var acts: [Act] = []
        var actIndex = 0
        var sceneIndex = 0
        var currentScenes: [Scene] = []
        func pushAct(_ title: String) {
            if actIndex > 0 { acts.append(Act(index: actIndex, title: acts.last?.title ?? title, scenes: currentScenes)) }
            actIndex += 1
            currentScenes = []
        }
        func pushScene(_ title: String) {
            sceneIndex += 1
            currentScenes.append(Scene(index: sceneIndex, title: title, beats: []))
        }
        for n in nodes {
            switch n.type {
            case .section(let level):
                if level == 1 { pushAct(n.rawText.trimmingCharacters(in: .whitespaces)) ; sceneIndex = 0 }
                else if level == 2 { pushScene(n.rawText.trimmingCharacters(in: .whitespaces)) }
            case .sceneHeading:
                pushScene(n.rawText.trimmingCharacters(in: .whitespaces))
            default: continue
            }
        }
        if actIndex == 0 { pushAct("ACT I") }
        // Append last act
        acts.append(Act(index: actIndex, title: acts.last?.title ?? "ACT I", scenes: currentScenes))
        return Structure(etag: computeETag(for: text), acts: acts)
    }
}

