import Foundation
import SwiftUI
import AppKit

@MainActor
final class UMPRecorder {
    static let shared = UMPRecorder()
    private var fh: FileHandle?
    private var url: URL?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
        let dir = root.appendingPathComponent(".fountain/corpus/ump", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let fn = "stream-\(df.string(from: Date())).ndjson"
        url = dir.appendingPathComponent(fn)
        fm.createFile(atPath: url!.path, contents: nil)
        fh = try? FileHandle(forWritingTo: url!)
        NotificationCenter.default.addObserver(self, selector: #selector(onUMPOut(_:)), name: .MetalCanvasUMPOut, object: nil)
    }

    @objc private func onUMPOut(_ noti: Notification) {
        guard let fh = fh else { return }
        var obj: [String: Any] = [:]
        obj["ts"] = ISO8601DateFormatter().string(from: Date())
        if let t = noti.userInfo?["topic"] { obj["topic"] = t }
        if let d = noti.userInfo?["data"] { obj["data"] = d }
        if let words = noti.userInfo?["words"] as? [UInt32] { obj["words"] = words.map { String(format: "0x%08X", $0) } }
        if let json = try? JSONSerialization.data(withJSONObject: obj) {
            fh.write(json); fh.write("\n".data(using: .utf8)!)
        }
    }
}

struct UMPRecorderBinder: View {
    var body: some View { Color.clear.onAppear { UMPRecorder.shared.start() } }
}
