import Foundation
import ArgumentParser

@main
struct MLSamplerSmoke: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Init sampler and play a short pattern (local, noninteractive)")

    @Option(name: .long, help: "BPM for pattern timing") var bpm: Double = 120
    @Option(name: .long, help: "Root MIDI note") var root: Int = 60

    func run() throws {
        #if canImport(MIDI2Sampler)
        let synth: LocalRenderSynth
        synth = SamplerSynth()
        synth.start()
        let notes = [0,2,4,7,12].map { UInt8(max(0, min(127, root + $0))) }
        let beat = 60.0 / bpm
        for n in notes {
            synth.noteOn(note: n, velocity: 100)
            Thread.sleep(forTimeInterval: beat * 0.4)
            synth.noteOff(note: n)
            Thread.sleep(forTimeInterval: beat * 0.1)
        }
        synth.stop()
        print("[sampler-smoke] completed")
        #else
        print("[sampler-smoke] MIDI2Sampler module not present; build with midi2sampler dependency")
        #endif
    }
}

