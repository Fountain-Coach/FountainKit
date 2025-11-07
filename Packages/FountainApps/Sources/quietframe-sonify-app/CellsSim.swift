import Foundation
import SwiftUI
import FountainAudioEngine

@MainActor final class CellAutomataSim: ObservableObject {
    static let shared = CellAutomataSim()

    @Published var width: Int = 64
    @Published var height: Int = 40
    @Published var wrap: Bool = true
    @Published var ruleName: String = "life"
    @Published var seedKind: String = "random" // random|hash|file
    @Published var seedHash: String = ""
    @Published var stepHz: Double = 8
    @Published var running: Bool = false
    @Published var density: Double = 0
    @Published var stateHash: String = ""

    // Core simulation logic
    private var core = AppCellsCore(width: 64, height: 40, wrap: true, ruleName: "life", seed: nil)
    private var timer: Timer? = nil

    init() {
        syncFromCore()
        reseedRandom()
    }

    func resize(width w: Int, height h: Int) {
        core.resize(width: w, height: h)
        syncFromCore()
        computeStats(); notify()
    }

    func reseedRandom() {
        seedKind = "random"
        core.reseedRandom()
        syncFromCore(); computeStats(); notify()
    }

    private func syncFromCore() {
        width = core.width
        height = core.height
        wrap = core.wrap
        ruleName = core.rule.rawValue
        seedKind = core.seedKind
        seedHash = core.seedHash
        density = core.density
        stateHash = core.stateHash
        objectWillChange.send()
    }

    func reseedFromHash(_ hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let val = UInt64(cleaned, radix: 16) else { return }
        seedKind = "hash"; seedHash = String(format: "%016llx", val)
        core.reseed(seed: val)
        syncFromCore(); computeStats(); notify()
    }

    func setRunning(_ on: Bool) { running = on; restartTimer() }
    func stepOnce() { tick() }
    func setStepHz(_ hz: Double) { stepHz = max(0.5, min(60.0, hz)); restartTimer() }

    private func restartTimer() {
        timer?.invalidate(); timer = nil
        guard running else { return }
        let iv = 1.0 / max(0.5, min(60.0, stepHz))
        timer = Timer.scheduledTimer(withTimeInterval: iv, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let tNs = DispatchTime.now().uptimeNanoseconds
        let births = core.tick() // (x,y,neighbors)
        syncFromCore(); computeStats()
        let events = emitNotes(births)
        notify()
        journalTick(tNs: tNs, births: births, ump: events)
    }

    private func emitNotes(_ births: [(Int,Int,Int)]) -> [[String: Any]] {
        guard let inst = QuietFrameInstrument.shared.instrument else { return [] }
        let cap = 128
        var count = 0
        var events: [[String: Any]] = []
        for (_,y,n) in births {
            let note = UInt8(36 + (y % 48))
            let vel = UInt8(min(127, max(20, 32 + n*16)))
            // Emit UMP (external visibility) and also trigger local engine for audibility
            inst.sendNoteOn(note: note, velocity7: vel)
            FountainAudioEngine.shared.noteOn(note: note, velocity: vel)
            MidiMonitorStore.shared.add(String(format: "Cells NoteOn n=%d v=%d", note, vel))
            let (w0, w1) = Self.makeCV2NoteOnWords(group: 0, channel: 0, note: note, velocity7: vel)
            journalUMPEvent(kind: "noteOn", note: note, velocity: vel, group: 0, channel: 0, w0: w0, w1: w1)
            SidecarBridge.shared.sendNoteEvent(["event":"noteOn","note":Int(note),"velocity":Int(vel),"channel":0,"group":0,"source":"cells"])            
            events.append(["type":"noteOn","note":Int(note),"velocity":Int(vel),"ump":[String(format: "0x%08X", w0), String(format: "0x%08X", w1)]])
            // Include a scheduled NoteOff marker in this tick's batch for visibility
            let (sw0, sw1) = Self.makeCV2NoteOffWords(group: 0, channel: 0, note: note, velocity7: 0)
            events.append(["type":"noteOffScheduled","note":Int(note),"delayMs":200,"ump":[String(format: "0x%08X", sw0), String(format: "0x%08X", sw1)]])

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                inst.sendNoteOff(note: note, velocity7: 0)
                FountainAudioEngine.shared.noteOff(note: note)
                MidiMonitorStore.shared.add(String(format: "Cells NoteOff n=%d", note))
                let (w0off, w1off) = Self.makeCV2NoteOffWords(group: 0, channel: 0, note: note, velocity7: 0)
                journalUMPEvent(kind: "noteOff", note: note, velocity: 0, group: 0, channel: 0, w0: w0off, w1: w1off)
                SidecarBridge.shared.sendNoteEvent(["event":"noteOff","note":Int(note),"channel":0,"group":0,"source":"cells"])            
                // We intentionally do not append to events here to keep per-tick cap stable; the NoteOff is visible via Sidecar.
            }
            count += 1; if count >= cap { break }
        }
        return events
    }

    private func computeStats() {
        density = core.density
        stateHash = core.stateHash
        objectWillChange.send()
    }

    private func notify() {
        guard let inst = QuietFrameInstrument.shared.instrument else { return }
        inst.sendPEProperties([
            "cells.grid.width": Double(width),
            "cells.grid.height": Double(height),
            "cells.grid.wrap": wrap ? 1.0 : 0.0,
            "cells.rule.name": 0.0, // write-only label; presence indicates change
            "cells.step.hz": stepHz,
            "cells.run.state": running ? 1.0 : 0.0,
            "cells.state.density": density,
            "cells.state.hash": 0.0
        ], command: .notify)
    }

    // -- Applied via CI/PE (mapped in sink.setUniform)
    func set(_ name: String, value: Double) {
        switch name {
        case "cells.grid.width": resize(width: Int(value), height: height)
        case "cells.grid.height": resize(width: width, height: Int(value))
        case "cells.grid.wrap": core.wrap = value >= 0.5; wrap = core.wrap; notify()
        case "cells.rule.name":
            // numeric code: 0=life,1=seeds,2=highlife,3=custom
            let code = Int(round(value))
            switch code { case 0: core.setRule("life"); case 1: core.setRule("seeds"); case 2: core.setRule("highlife"); default: core.setRule("custom") }
            ruleName = core.rule.rawValue
            notify()
        case "cells.seed.reseed": reseedRandom()
        case "cells.step.hz": setStepHz(value)
        case "cells.run.state": setRunning(value >= 0.5)
        case "cells.step.once": stepOnce()
        default: break
        }
    }

    func setString(name: String, value: String) {
        switch name {
        case "cells.rule.name": ruleName = value.lowercased(); notify()
        case "cells.seed.kind": seedKind = value.lowercased(); if seedKind == "random" { reseedRandom() }
        case "cells.seed.hash": reseedFromHash(value)
        default: break
        }
    }

    func snapshotNumeric() -> [String: Double] {
        return [
            "cells.grid.width": Double(width),
            "cells.grid.height": Double(height),
            "cells.grid.wrap": wrap ? 1.0 : 0.0,
            "cells.step.hz": stepHz,
            "cells.run.state": running ? 1.0 : 0.0,
            "cells.state.density": density
        ]
    }

    func snapshotPE() -> [String: Any] {
        var out: [String: Any] = snapshotNumeric()
        let strings = core.snapshotStrings()
        for (k,v) in strings { out[k] = v }
        return out
    }

    // MARK: - UMP helpers (hex words for journal)
    private static func makeCV2NoteOnWords(group: UInt8, channel: UInt8, note: UInt8, velocity7: UInt8) -> (UInt32, UInt32) {
        let g = UInt32(group & 0x0F)
        let ch = UInt32(channel & 0x0F)
        let n = UInt32(note & 0x7F)
        let w0 = (UInt32(0x4) << 28) | (g << 24) | (UInt32(0x9) << 20) | (ch << 16) | (n << 8)
        let v16 = UInt16((UInt32(velocity7) * 65535) / 127)
        let w1 = UInt32(v16) << 16
        return (w0, w1)
    }
    private static func makeCV2NoteOffWords(group: UInt8, channel: UInt8, note: UInt8, velocity7: UInt8) -> (UInt32, UInt32) {
        let g = UInt32(group & 0x0F)
        let ch = UInt32(channel & 0x0F)
        let n = UInt32(note & 0x7F)
        let w0 = (UInt32(0x4) << 28) | (g << 24) | (UInt32(0x8) << 20) | (ch << 16) | (n << 8)
        let v16 = UInt16((UInt32(velocity7) * 65535) / 127)
        let w1 = UInt32(v16) << 16
        return (w0, w1)
    }

    // Draw helper
    func forEachAlive(_ body: (Int,Int,UInt8) -> Void) { core.forEachAlive(body) }
}

// MARK: - Journal
extension CellAutomataSim {
    private func journalTick(tNs: UInt64, births: [(Int,Int,Int)], ump: [[String: Any]]) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let dir = root.appendingPathComponent(".fountain/artifacts/quietframe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = dir.appendingPathComponent("journal-\(stamp.prefix(19)).ndjson")
        let entry: [String: Any] = [
            "tNs": String(tNs),
            "cells": ["density": density, "width": width, "height": height, "wrap": wrap, "rule": ruleName],
            "births": births.prefix(16).map { ["x": $0.0, "y": $0.1, "n": $0.2] },
            "ump": ump
        ]
        if let data = try? JSONSerialization.data(withJSONObject: entry), var s = String(data: data, encoding: .utf8) {
            s.append("\n"); try? s.data(using: .utf8)?.appendOrWrite(to: file)
        }
    }

    private func journalUMPEvent(kind: String, note: UInt8, velocity: UInt8, group: UInt8, channel: UInt8, w0: UInt32, w1: UInt32) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let dir = root.appendingPathComponent(".fountain/artifacts/quietframe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("journal-events.ndjson")
        let entry: [String: Any] = [
            "tNs": String(DispatchTime.now().uptimeNanoseconds),
            "kind": kind,
            "note": Int(note),
            "velocity": Int(velocity),
            "group": Int(group),
            "channel": Int(channel),
            "ump": [String(format: "0x%08X", w0), String(format: "0x%08X", w1)]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: entry), var s = String(data: data, encoding: .utf8) {
            s.append("\n"); try? s.data(using: .utf8)?.appendOrWrite(to: file)
        }
    }
}

fileprivate extension Data {
    func appendOrWrite(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd(); try handle.write(contentsOf: self); try handle.close()
        } else { try write(to: url) }
    }
}

struct CellsView: View {
    var frameSize: CGSize
    @ObservedObject var sim: CellAutomataSim = .shared
    var body: some View {
        Canvas { ctx, size in
            let dx = frameSize.width / CGFloat(max(1, sim.width))
            let dy = frameSize.height / CGFloat(max(1, sim.height))
            sim.forEachAlive { x,y,age in
                let r = CGRect(x: CGFloat(x)*dx - frameSize.width*0.5 + size.width*0.5,
                               y: CGFloat(y)*dy - frameSize.height*0.5 + size.height*0.5,
                               width: dx, height: dy)
                let a = Double(min(1.0, 0.3 + Double(age)/12.0))
                ctx.fill(Path(r), with: .color(Color.blue.opacity(a)))
            }
        }
    }
}
