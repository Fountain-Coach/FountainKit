import SwiftUI
import MetalKit

struct MetalGridLayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let v = MTKView()
        v.enableSetNeedsDisplay = true
        v.isPaused = true
        v.clearColor = MTLClearColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 1.0)
        return v
    }
    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)
    }
}

