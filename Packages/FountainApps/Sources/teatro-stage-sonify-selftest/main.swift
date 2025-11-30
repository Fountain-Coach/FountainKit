import Foundation
import AVFoundation

@main
struct TeatroStageSonifySelfTest {
    static func main() throws {
        let sampleRate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let engine = AVAudioEngine()

        var phase: Double = 0
        let freq = 440.0
        let gain = 0.4
        let twoPi = 2.0 * Double.pi
        let sr = sampleRate

        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = Int(frameCount)
            let phaseInc = twoPi * freq / sr
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<frames {
                let sample = sin(phase) * gain
                phase += phaseInc
                if phase > twoPi { phase -= twoPi }
                for buf in abl {
                    buf.mData!.assumingMemoryBound(to: Float.self)[frame] = Float(sample)
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()

        let targetFrames = Int(sampleRate * 0.5) // half a second
        var rendered = 0
        var accumEnergy = 0.0
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!

        while rendered < targetFrames {
            let framesToRender = min(Int(engine.manualRenderingMaximumFrameCount), targetFrames - rendered)
            let status = try engine.renderOffline(AVAudioFrameCount(framesToRender), to: buffer)
            guard status == .success else {
                fputs("render failed with status \(status)\n", stderr)
                exit(2)
            }
            let frames = Int(buffer.frameLength)
            guard let channelData = buffer.floatChannelData else { fputs("missing channel data\n", stderr); exit(2) }
            let channels = Int(buffer.format.channelCount)
            for c in 0..<channels {
                let ptr = channelData[c]
                for i in 0..<frames {
                    let s = Double(ptr[i])
                    accumEnergy += s * s
                }
            }
            rendered += frames
        }

        engine.stop()
        let totalSamples = Double(rendered * Int(buffer.format.channelCount))
        let rms = sqrt(accumEnergy / max(totalSamples, 1))
        print(String(format: "audio_selftest_rms=%.4f", rms))
        if rms < 0.01 {
            fputs("Audio self-test failed: RMS too low\n", stderr)
            exit(1)
        }
    }
}
