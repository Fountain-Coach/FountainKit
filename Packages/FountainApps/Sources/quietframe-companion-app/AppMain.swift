import SwiftUI
import AppKit

@main
struct QuietFrameCompanionApp: App {
    var body: some Scene {
        WindowGroup("QuietFrame Companion") {
            CompanionRootView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}

struct CompanionRootView: View {
    @StateObject private var pe = QuietFramePEClient()
    @State private var master: Double = 0.8
    @State private var muted: Bool = false
    @State private var droneLPF: Double = 1200
    @State private var droneAmp: Double = 0.2
    @State private var clockLevel: Double = 0.15
    @State private var clockDiv: Double = 2
    @State private var breathLevel: Double = 0.08
    @State private var overMix: Double = 0.0
    @State private var fxDelayMix: Double = 0.04
    @State private var bpm: Double = 96
    @State private var section: Double = 1
    var body: some View {
        let inspector = Group {
            HStack {
                Text("PE Inspector").font(.headline)
                Spacer()
                Button("Connect") { pe.connect() }
            }
            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow { Text("State").font(.caption); Text(pe.recState.capitalized).font(.caption).bold() }
                    if let url = pe.lastSavedURL {
                        GridRow { Text("Saved").font(.caption); Text(url).font(.caption2).truncationMode(.middle).lineLimit(1) }
                    }
                    GridRow { Text("Master").font(.caption); Slider(value: $master, in: 0...1).frame(width: 160).onChange(of: master) { _, v in pe.set([("engine.masterGain", v)]) } }
                    GridRow { Text("Mute").font(.caption); Toggle("", isOn: $muted).toggleStyle(.switch).onChange(of: muted) { _, v in pe.set([("audio.muted", v ? 1.0 : 0.0)]) } }
                    GridRow { Text("Drone LPF").font(.caption); Slider(value: $droneLPF, in: 50...8000).frame(width: 160).onChange(of: droneLPF) { _, v in pe.set([("drone.lpfHz", v)]) } }
                    GridRow { Text("Drone Amp").font(.caption); Slider(value: $droneAmp, in: 0...1).frame(width: 160).onChange(of: droneAmp) { _, v in pe.set([("drone.amp", v)]) } }
                    GridRow { Text("Clock Level").font(.caption); Slider(value: $clockLevel, in: 0...1).frame(width: 160).onChange(of: clockLevel) { _, v in pe.set([("clock.level", v)]) } }
                    GridRow { Text("Clock Div").font(.caption); Slider(value: $clockDiv, in: 1...8, step: 1).frame(width: 160).onChange(of: clockDiv) { _, v in pe.set([("clock.div", v)]) } }
                    GridRow { Text("Breath Level").font(.caption); Slider(value: $breathLevel, in: 0...1).frame(width: 160).onChange(of: breathLevel) { _, v in pe.set([("breath.level", v)]) } }
                    GridRow { Text("Overtones Mix").font(.caption); Slider(value: $overMix, in: 0...1).frame(width: 160).onChange(of: overMix) { _, v in pe.set([("overtones.mix", v)]) } }
                    GridRow { Text("Delay Mix").font(.caption); Slider(value: $fxDelayMix, in: 0...0.5).frame(width: 160).onChange(of: fxDelayMix) { _, v in pe.set([("fx.delay.mix", v)]) } }
                    GridRow { Text("BPM").font(.caption); Slider(value: $bpm, in: 60...180, step: 1).frame(width: 160).onChange(of: bpm) { _, v in pe.set([("tempo.bpm", v)]) } }
                    GridRow { Text("Section").font(.caption); Slider(value: $section, in: 1...9, step: 1).frame(width: 160).onChange(of: section) { _, v in pe.set([("act.section", v)]) } }
                    GridRow { Button("GET Snapshot") { pe.get() } }
                    Divider()
                    GridRow {
                        Button { pe.sendVendor(topic: "rec.start") } label: { Label("Record", systemImage: "record.circle") }
                        Button { pe.sendVendor(topic: "rec.stop") } label: { Label("Stop", systemImage: "stop.circle") }
                    }
                }
            } label: { Text(pe.connectedName ?? "Not connected").font(.caption) }
            TextEditor(text: $pe.lastSnapshotJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 140)
            Spacer()
        }
        return VStack(alignment: .leading, spacing: 8) { inspector }
            .padding(12)
            .frame(minWidth: 640, minHeight: 480)
            .background(Color(NSColor.windowBackgroundColor))
    }
}
