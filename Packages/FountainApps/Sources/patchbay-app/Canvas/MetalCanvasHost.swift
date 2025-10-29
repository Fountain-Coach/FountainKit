import SwiftUI
import MetalViewKit

struct MetalCanvasHost: View {
    @EnvironmentObject var vm: EditorVM
    @EnvironmentObject var state: AppState
    var body: some View {
        ZStack(alignment: .topLeading) {
            UMPRecorderBinder()
            MetalCanvasView(zoom: vm.zoom, translation: vm.translation, gridMinor: CGFloat(vm.grid), majorEvery: vm.majorEvery, nodes: {
                // Map Stage nodes for now; other kinds can be added later
                var nodes: [MetalCanvasNode] = []
                for n in vm.nodes {
                    if let dash = state.dashboard[n.id], dash.kind == .stageA4 {
                        let rect = CGRect(x: CGFloat(n.x), y: CGFloat(n.y), width: CGFloat(n.w), height: CGFloat(n.h))
                        let page = dash.props["page"] ?? "A4"
                        let parts = (dash.props["margins"] ?? "18,18,18,18").split(separator: ",").compactMap{ Double($0.trimmingCharacters(in: .whitespaces)) }
                        let m = (parts.count == 4) ? MVKMargins(top: parts[0], leading: parts[1], bottom: parts[2], trailing: parts[3]) : MVKMargins(top: 18, leading: 18, bottom: 18, trailing: 18)
                        let bl = CGFloat(Double(dash.props["baseline"] ?? "12") ?? 12)
                        nodes.append(StageMetalNode(id: n.id, frameDoc: rect, title: dash.props["title"] ?? (n.title ?? n.id), page: page, margins: m, baseline: bl))
                    }
                }
                return nodes
            }, edges: {
                // Map VM edges to MetalCanvasEdge by splitting refs like "A.out"
                var out: [MetalCanvasEdge] = []
                for e in vm.edges {
                    let fp = e.from.split(separator: ".", maxSplits: 1).map(String.init)
                    let tp = e.to.split(separator: ".", maxSplits: 1).map(String.init)
                    if fp.count == 2, tp.count == 2 {
                        out.append(MetalCanvasEdge(fromNode: fp[0], fromPort: fp[1], toNode: tp[0], toPort: tp[1]))
                    }
                }
                return out
            }, instrument: MetalInstrumentDescriptor(manufacturer: "Fountain", product: "PatchBayCanvas", instanceId: "main", displayName: "PatchBay Canvas"))
            // Right-edge hover hit area for MIDI monitor
            MidiMonitorHitArea()
            // HUD: zoom and origin
            Text(String(format: "Zoom %.2fx  Origin (%.0f, %.0f)", Double(vm.zoom), Double(vm.translation.x), Double(vm.translation.y)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding(8)
            // MIDI 2.0 Monitor overlay (top-right, fades when idle; jumps to full on hover)
            Midi2MonitorOverlay(isHot: MidiMonitorHitArea.hotBinding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
    }
}

// A shared hover detector so the monitor overlay can pause its fade when the right edge is touched.
fileprivate struct MidiMonitorHitArea: View {
    @State private var hovering = false
    static private var _hot: Bool = false
    static var hotBinding: Binding<Bool> {
        Binding(get: { _hot }, set: { _ in })
    }
    var body: some View {
        Color.clear
            .frame(maxHeight: .infinity)
            .frame(width: 56)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                Self._hot = inside
            }
    }
}
