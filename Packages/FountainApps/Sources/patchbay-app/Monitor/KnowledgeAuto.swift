import Foundation
import AppKit

@MainActor
enum KnowledgeAuto {
    private static var timer: Timer?
    static func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task { @MainActor in
                if let url = try? StoryLogHarvester.harvestAll() {
                    // Maintain a stable symlink for quick access: knowledge-latest.json
                    let fm = FileManager.default
                    let latest = url.deletingLastPathComponent().appendingPathComponent("knowledge-latest.json")
                    try? fm.removeItem(at: latest)
                    try? fm.copyItem(at: url, to: latest)
                }
            }
        }
    }
}
