import Foundation
import MIDI2
import MIDI2CI

@MainActor public protocol QFPECoreDelegate: AnyObject {
    func peDidUpdateSnapshot(json: String)
    func peDidEmitUMPEvent(json: String)
}

@MainActor public final class QFPEClientCore {
    public weak var delegate: (any QFPECoreDelegate)?
    public init() {}

    // Nonisolated entry: feed UMP words (SysEx7) and decode
    public func handleSysEx7UMP(words: [UInt32]) {
        let bytes = QFUMP.unpackSysEx7(words: words)
        guard !bytes.isEmpty else { return }
        if let env = try? MidiCiEnvelope(sysEx7Payload: bytes) {
            switch env.body {
            case .propertyExchange(let pe):
                if pe.command == .getReply || pe.command == .notify {
                    if let obj = try? JSONSerialization.jsonObject(with: Data(pe.data)) as? [String: Any] {
                        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]), let s = String(data: data, encoding: .utf8) {
                            self.delegate?.peDidUpdateSnapshot(json: s)
                        }
                    }
                }
            default: break
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["dir":"in","ump": words.map { String(format: "0x%08X", $0) }], options: []), let s = String(data: data, encoding: .utf8) { self.delegate?.peDidEmitUMPEvent(json: s) }
    }
}
