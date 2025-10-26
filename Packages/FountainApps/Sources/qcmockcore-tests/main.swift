import Foundation
import CoreGraphics
import QCMockCore

@main
struct Runner {
    static func main() {
        var failures = 0
        func assert(_ cond: @autoclosure () -> Bool, _ name: String, _ msg: String = "") {
            if !cond() { failures += 1; fputs("FAIL: \(name) \(msg)\n", stderr) } else { print("PASS: \(name)") }
        }

        // Round-trip
        do {
            let xf = CanvasTransform(scale: 2.0, translation: CGPoint(x: 10, y: -5))
            let p = CGPoint(x: 12.3, y: -7.7)
            let v = xf.docToView(p)
            let back = xf.viewToDoc(v)
            assert(abs(back.x - p.x) < 1e-6 && abs(back.y - p.y) < 1e-6, "roundtrip")
        }

        // Anchor zoom
        do {
            var xf = CanvasTransform(scale: 1.0, translation: .zero)
            let anchorView = CGPoint(x: 200, y: 150)
            let beforeDoc = xf.viewToDoc(anchorView)
            xf.zoom(around: anchorView, factor: 1.5)
            let after = xf.docToView(beforeDoc)
            assert(abs(after.x - anchorView.x) < 1e-5 && abs(after.y - anchorView.y) < 1e-5, "anchorZoom")
        }

        // Grid decimation
        do {
            let dec1 = GridModel.decimation(minorStepDoc: 24, scale: 0.25)
            assert(!dec1.showMinor && dec1.showLabels, "decimation.low")
            let dec2 = GridModel.decimation(minorStepDoc: 24, scale: 0.5)
            assert(dec2.showMinor && dec2.showLabels, "decimation.med")
        }

        // Non-scaling stroke width
        do {
            let w = GridModel.nonScalingStrokeWidth(desiredPixels: 1.0, scale: 2.0)
            assert(abs(w - 0.5) < 1e-6, "nssw")
        }

        if failures > 0 { fputs("FAILURES: \(failures)\n", stderr); exit(1) }
        print("ALL PASS")
    }
}

