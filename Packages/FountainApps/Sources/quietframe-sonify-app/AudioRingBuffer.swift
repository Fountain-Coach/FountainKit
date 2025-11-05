import Foundation

// Lock-light stereo float ring buffer for audio callback handoff.
final class AudioRingBuffer {
    private let channels = 2
    private let capacityFrames: Int
    private let buf: UnsafeMutablePointer<Float>
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var countFrames: Int = 0
    private let lock = NSLock()

    init(capacityFrames: Int) {
        self.capacityFrames = max(1, capacityFrames)
        self.buf = .allocate(capacity: capacityFrames * channels)
        self.buf.initialize(repeating: 0, count: capacityFrames * channels)
    }

    deinit {
        buf.deinitialize(count: capacityFrames * channels)
        buf.deallocate()
    }

    // Write interleaved stereo samples; returns frames written (may drop if full)
    func writeStereo(left lp: UnsafePointer<Float>, right rp: UnsafePointer<Float>, frames n: Int) -> Int {
        guard n > 0 else { return 0 }
        lock.lock(); defer { lock.unlock() }
        let free = capacityFrames - countFrames
        let toWrite = min(free, n)
        if toWrite <= 0 { return 0 }
        var wi = writeIndex
        for i in 0..<toWrite {
            let dst = buf.advanced(by: ((wi + i) % capacityFrames) * channels)
            dst[0] = lp[i]
            dst[1] = rp[i]
        }
        wi = (wi + toWrite) % capacityFrames
        writeIndex = wi
        countFrames += toWrite
        return toWrite
    }

    // Read up to 'frames' interleaved into provided Data (resized). Returns frames read.
    func readInterleaved(into data: inout Data, frames n: Int) -> Int {
        guard n > 0 else { return 0 }
        lock.lock(); defer { lock.unlock() }
        let toRead = min(countFrames, n)
        if toRead <= 0 { return 0 }
        data.count = toRead * channels * MemoryLayout<Float>.size
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Float.self).baseAddress!
            var ri = readIndex
            for i in 0..<toRead {
                let src = buf.advanced(by: ((ri + i) % capacityFrames) * channels)
                out[2*i] = src[0]
                out[2*i+1] = src[1]
            }
        }
        readIndex = (readIndex + toRead) % capacityFrames
        countFrames -= toRead
        return toRead
    }
}

