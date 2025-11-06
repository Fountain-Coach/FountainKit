import Foundation
import QuietFrameKit

@MainActor final class SidecarInbound: ObservableObject {
    private let client: QuietFrameSidecarClient
    init(targetName: String = "QuietFrame") {
        self.client = QuietFrameSidecarClient(config: .init(targetDisplayName: targetName))
        Task { [weak weakSelf = self] in
            guard let weakSelf else { return }
            await weakSelf.client.startPolling(pollIntervalMs: 150)
            await weakSelf.client.setUMPSink { words in
                Task { @MainActor in weakSelf.handle(words: words) }
            }
        }
    }

    private func handle(words: [UInt32]) {
        let bytes = unpackSysEx7(words: words)
        guard bytes.count >= 8 else { return }
        // Vendor JSON header 0xF0, 0x7D, 'J','S','N', 0x00 ... 0xF7
        if bytes[0] == 0xF0, bytes[1] == 0x7D, bytes[2] == 0x4A, bytes[3] == 0x53, bytes[4] == 0x4E, bytes[5] == 0x00, bytes.last == 0xF7 {
            let body = Data(bytes[6..<(bytes.count-1)])
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let topic = obj["topic"] as? String {
                switch topic {
                case "rec.start": NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordCommand"), object: nil, userInfo: ["op":"start"])
                case "rec.stop": NotificationCenter.default.post(name: Notification.Name("QuietFrameRecordCommand"), object: nil, userInfo: ["op":"stop"])
                default: break
                }
            }
        }
    }

    private func unpackSysEx7(words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i + 1 < words.count {
            let w1 = words[i], w2 = words[i+1]
            if ((w1 >> 28) & 0xF) != 0x3 { break }
            let n = Int((w1 >> 16) & 0xF)
            let d0 = UInt8((w1 >> 8) & 0xFF)
            let d1 = UInt8(w1 & 0xFF)
            let d2 = UInt8((w2 >> 24) & 0xFF)
            let d3 = UInt8((w2 >> 16) & 0xFF)
            let d4 = UInt8((w2 >> 8) & 0xFF)
            let d5 = UInt8(w2 & 0xFF)
            out.append(contentsOf: [d0,d1,d2,d3,d4,d5].prefix(n))
            let status = UInt8((w1 >> 20) & 0xF)
            i += 2
            if status == 0x0 || status == 0x3 { break }
        }
        return out
    }
}
