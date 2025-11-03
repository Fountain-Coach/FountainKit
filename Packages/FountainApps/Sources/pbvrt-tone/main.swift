import Foundation
import AVFoundation

@main
struct PBVRTToneApp {
    static func main() {
        var freqA: Double = 440
        var durA: Double = 1.2
        var freqB: Double? = nil
        var durB: Double = 1.2
        var amp: Double = 0.25
        var sr: Double = 48_000

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--freq": if let v = it.next(), let d = Double(v) { freqA = d }
            case "--dur": if let v = it.next(), let d = Double(v) { durA = d }
            case "--freq2": if let v = it.next(), let d = Double(v) { freqB = d }
            case "--dur2": if let v = it.next(), let d = Double(v) { durB = d }
            case "--amp": if let v = it.next(), let d = Double(v) { amp = d }
            case "--sr": if let v = it.next(), let d = Double(v) { sr = d }
            case "-h", "--help":
                FileHandle.standardOutput.write(Data("PBVRT Tone Player\nUsage: pbvrt-tone [--freq 440] [--dur 1.2] [--freq2 443] [--dur2 1.2] [--amp 0.25] [--sr 48000]\n".utf8))
                return
            default: break
            }
        }

        func makeBuffer(freq: Double, dur: Double) -> AVAudioPCMBuffer {
            let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
            let frameCount = AVAudioFrameCount(dur * sr)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            let ptr = buffer.floatChannelData![0]
            let w = 2.0 * Double.pi * freq / sr
            for i in 0..<Int(frameCount) {
                let s = sin(Double(i) * w)
                ptr[i] = Float(amp * s)
            }
            return buffer
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1))
        do { try engine.start() } catch {
            FileHandle.standardError.write(Data("Failed to start AVAudioEngine: \(error)\n".utf8))
            return
        }
        player.play()
        let bufA = makeBuffer(freq: freqA, dur: durA)
        player.scheduleBuffer(bufA, at: nil, options: [])
        if let f2 = freqB {
            let when = AVAudioTime(hostTime: mach_absolute_time() + UInt64(1_000_000_000 * durA))
            let bufB = makeBuffer(freq: f2, dur: durB)
            player.scheduleBuffer(bufB, at: when, options: [])
        }
        let totalDur = durA + (freqB != nil ? durB : 0)
        RunLoop.current.run(until: Date().addingTimeInterval(totalDur + 0.1))
        player.stop(); engine.stop()
    }
}

