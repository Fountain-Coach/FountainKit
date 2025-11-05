import SwiftUI

/// Listens for cursor movement over a designated "Quiet Frame" node and
/// drives MIDI 2.0 CC/notes on the Csound Bridge instrument for sonification.
struct SaliencyOverlay: View {
    @EnvironmentObject var vm: EditorVM
    @State private var lastInside: Bool = false
    @State private var lastNote: UInt8 = 0
    @State private var lastVelocity: UInt8 = 0
    @State private var lastPulse: Date = .distantPast

    var body: some View {
        Color.clear
            .onAppear { attach() }
    }

    private func attach() {
        NotificationCenter.default.addObserver(forName: .MetalCanvasMIDIActivity, object: nil, queue: .main) { note in
            guard let info = note.userInfo, let type = info["type"] as? String else { return }
            if type == "ui.cursor.move" {
                let dx = (info["doc.x"] as? NSNumber)?.doubleValue ?? 0
                let dy = (info["doc.y"] as? NSNumber)?.doubleValue ?? 0
                handleCursor(doc: CGPoint(x: dx, y: dy))
            } else if type == "llm.pulse" {
                // Pulse edge glow (optional hook); no-op by default
                lastPulse = Date()
            }
        }
    }

    private func quietFrameNode() -> PBNode? {
        // Prefer id="quietframe" if present; otherwise title match.
        if let n = vm.nodes.first(where: { $0.id.lowercased() == "quietframe" }) { return n }
        return vm.nodes.first(where: { ($0.title ?? "").lowercased().contains("quiet frame") })
    }

    private func handleCursor(doc p: CGPoint) {
        guard let n = quietFrameNode() else { return }
        let rect = CGRect(x: CGFloat(n.x), y: CGFloat(n.y), width: CGFloat(n.w), height: CGFloat(n.h))
        let inside = rect.contains(p)
        let intensity: Double = {
            guard inside else { return 0 }
            // Simple saliency = 1 - normalized distance from center (clamped)
            let cx = rect.midX, cy = rect.midY
            let dx = Double(abs(p.x - cx)) / Double(max(1, rect.width) * 0.5)
            let dy = Double(abs(p.y - cy)) / Double(max(1, rect.height) * 0.5)
            let d = min(1.0, sqrt(dx*dx + dy*dy))
            return max(0, 1.0 - d)
        }()

        driveCsound(intensity: intensity)
        if intensity > 0 {
            // Visualise flow: QuietFrame.out → Csound.in
            vm.transientGlowEdge(fromRef: "quietframe.out", toRef: "csound.in", duration: 0.8)
        }
        lastInside = inside
    }

    private func driveCsound(intensity: Double) {
        guard let inst = CsoundBridgeHolder.shared.instrument else { return }
        let v7 = UInt8(max(0, min(127, Int((intensity * 127.0).rounded()))))
        // CC1 (mod wheel) as saliency level
        inst.sendCC(controller: 1, value7: v7)
        // Map intensity to a simple pentatonic scale around middle C
        let scale: [UInt8] = [60, 62, 65, 67, 69, 72]
        let idx = min(scale.count - 1, max(0, Int((intensity * Double(scale.count)).rounded()) ))
        let note = scale[idx]
        let vel: UInt8 = max(20, v7)
        if note != lastNote || abs(Int(vel) - Int(lastVelocity)) > 8 {
            if lastNote != 0 { inst.sendNoteOff(note: lastNote, velocity7: 0) }
            inst.sendNoteOn(note: note, velocity7: vel)
            lastNote = note
            lastVelocity = vel
        }
    }
}
