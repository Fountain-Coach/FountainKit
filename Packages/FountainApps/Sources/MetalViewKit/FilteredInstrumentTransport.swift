import Foundation

public struct RouteFilterSpec: Sendable {
    public var group: UInt8? // override group if set
    public var channelMaskAll: Bool
    public var channels: Set<UInt8> // 0-15 channel indices (MIDI semantics: 0 = ch1)
    public var allowCV2: Bool
    public var allowM1: Bool
    public var allowPE: Bool
    public var allowUtility: Bool
    public init(group: UInt8?, channelMaskAll: Bool, channels: Set<UInt8>, allowCV2: Bool, allowM1: Bool, allowPE: Bool, allowUtility: Bool) {
        self.group = group
        self.channelMaskAll = channelMaskAll
        self.channels = channels
        self.allowCV2 = allowCV2
        self.allowM1 = allowM1
        self.allowPE = allowPE
        self.allowUtility = allowUtility
    }
}

public final class FilteredMetalInstrumentTransport: MetalInstrumentTransport, @unchecked Sendable {
    private let base: any MetalInstrumentTransport
    private let filter: RouteFilterSpec
    public init(base: any MetalInstrumentTransport, filter: RouteFilterSpec) {
        self.base = base
        self.filter = filter
    }

    public func makeSession(
        descriptor: MetalInstrumentDescriptor,
        receiveUMP: @escaping @Sendable ([UInt32]) -> Void
    ) throws -> MetalInstrumentTransportSession {
        let inner = try base.makeSession(descriptor: descriptor, receiveUMP: receiveUMP)
        return FilteredSession(inner: inner, filter: filter)
    }

    private final class FilteredSession: MetalInstrumentTransportSession, @unchecked Sendable {
        private let inner: any MetalInstrumentTransportSession
        private let filter: RouteFilterSpec
        init(inner: any MetalInstrumentTransportSession, filter: RouteFilterSpec) {
            self.inner = inner
            self.filter = filter
        }

        func send(words: [UInt32]) {
            var out: [UInt32] = []
            var i = 0
            while i < words.count {
                let w0 = words[i]
                let mt = UInt8((w0 >> 28) & 0xF)
                let count = wordCount(for: mt)
                let end = min(words.count, i + count)
                let slice = Array(words[i..<end])

                if shouldPass(mt: mt, firstWord: w0), let modified = applyGroupAndChannel(slice) {
                    out.append(contentsOf: modified)
                }
                i = end
            }
            if !out.isEmpty { inner.send(words: out) }
        }

        func close() { inner.close() }

        private func wordCount(for mt: UInt8) -> Int {
            switch mt {
            case 0x4: return 2 // MIDI 2.0 CV
            case 0x2: return 1 // MIDI 1.0 CV
            case 0x3: return 2 // SysEx7 in 2-word chunks
            case 0x0, 0x1: return 1 // Utility, System Common/Real-Time
            default: return 2
            }
        }

        private func shouldPass(mt: UInt8, firstWord w0: UInt32) -> Bool {
            switch mt {
            case 0x4: return filter.allowCV2
            case 0x2: return filter.allowM1
            case 0x3: return filter.allowPE
            case 0x0: return filter.allowUtility
            default: return true
            }
        }

        private func applyGroupAndChannel(_ msg: [UInt32]) -> [UInt32]? {
            guard var w0 = msg.first else { return msg }
            // Channel mask (for messages that carry channel: 0x4 and 0x2)
            let mt = UInt8((w0 >> 28) & 0xF)
            if mt == 0x4 || mt == 0x2 {
                if !filter.channelMaskAll {
                    let ch = UInt8((w0 >> 16) & 0xF)
                    if !filter.channels.contains(ch) { return nil }
                }
            }
            // Group override
            if let g = filter.group { w0 = (w0 & 0xF0FF_FFFF) | (UInt32(g & 0x0F) << 24) }
            if msg.count == 1 { return [w0] }
            var out = msg
            out[0] = w0
            return out
        }
    }
}
