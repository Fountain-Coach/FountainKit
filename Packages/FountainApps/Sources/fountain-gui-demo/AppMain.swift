import AppKit
import FountainGUIKit

private struct DemoState {
    var zoom: CGFloat = 1.0
    var translation: CGPoint = .zero
    var rotation: CGFloat = 0.0
}

@MainActor
private final class DemoSurfaceView: FGKRootView {
    var state = DemoState()

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(bounds)

        context.saveGState()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context.translateBy(x: center.x + state.translation.x, y: center.y + state.translation.y)
        context.scaleBy(x: state.zoom, y: state.zoom)
        context.rotate(by: state.rotation)

        let rect = CGRect(x: -40.0, y: -40.0, width: 80.0, height: 80.0)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(rect)

        context.restoreGState()
    }
}

@MainActor
private final class DemoInstrumentTarget: FGKEventTarget, FGKPropertyConsumer {
    private unowned let view: DemoSurfaceView
    private let node: FGKNode
    private var lastDragLocation: NSPoint?

    init(view: DemoSurfaceView, node: FGKNode) {
        self.view = view
        self.node = node
    }

    func handle(event: FGKEvent) -> Bool {
        switch event {
        case .mouseDown(let mouse):
            lastDragLocation = mouse.locationInView
            fputs("[FGKDemo] mouseDown at=\(mouse.locationInView)\n", stderr)
        case .mouseUp(let mouse):
            lastDragLocation = nil
            fputs("[FGKDemo] mouseUp at=\(mouse.locationInView)\n", stderr)
        case .mouseDragged(let mouse):
            if let last = lastDragLocation {
                let dx = mouse.locationInView.x - last.x
                let dy = mouse.locationInView.y - last.y
                lastDragLocation = mouse.locationInView
                applyPan(dx: dx, dy: dy)
            }
            fputs("[FGKDemo] mouseDragged at=\(mouse.locationInView)\n", stderr)
        case .scroll(let scroll):
            applyPan(dx: CGFloat(scroll.deltaX), dy: CGFloat(scroll.deltaY))
            fputs("[FGKDemo] scroll dx=\(scroll.deltaX) dy=\(scroll.deltaY) at=\(scroll.locationInView)\n", stderr)
        case .magnify(let magnify):
            applyZoom(factor: 1.0 + CGFloat(magnify.magnification))
            fputs("[FGKDemo] magnify m=\(magnify.magnification) at=\(magnify.locationInView)\n", stderr)
        case .rotate(let rotate):
            let radians = CGFloat(rotate.rotation) * .pi / 180.0
            applyRotation(delta: radians)
            fputs("[FGKDemo] rotate r=\(rotate.rotation) at=\(rotate.locationInView)\n", stderr)
        case .swipe(let swipe):
            fputs("[FGKDemo] swipe dx=\(swipe.deltaX) dy=\(swipe.deltaY) at=\(swipe.locationInView)\n", stderr)
        case .keyDown(let key):
            fputs("[FGKDemo] keyDown chars=\(key.characters) code=\(key.keyCode)\n", stderr)
        case .keyUp(let key):
            fputs("[FGKDemo] keyUp chars=\(key.characters) code=\(key.keyCode)\n", stderr)
        case .mouseMoved(let mouse):
            fputs("[FGKDemo] mouseMoved at=\(mouse.locationInView)\n", stderr)
        }
        return true
    }

    func setProperty(_ name: String, value: FGKPropertyValue) {
        switch (name, value) {
        case ("canvas.zoom", .float(let v)):
            view.state.zoom = CGFloat(min(max(v, 0.2), 5.0))
        case ("canvas.translation.x", .float(let v)):
            view.state.translation.x = CGFloat(v)
        case ("canvas.translation.y", .float(let v)):
            view.state.translation.y = CGFloat(v)
        case ("canvas.rotation", .float(let v)):
            view.state.rotation = CGFloat(v)
        default:
            break
        }
        view.needsDisplay = true
    }

    private func applyPan(dx: CGFloat, dy: CGFloat) {
        let newX = Double(view.state.translation.x + dx)
        let newY = Double(view.state.translation.y + dy)
        _ = node.setProperty("canvas.translation.x", value: .float(newX))
        _ = node.setProperty("canvas.translation.y", value: .float(newY))
    }

    private func applyZoom(factor: CGFloat) {
        let current = Double(view.state.zoom)
        let next = min(max(current * Double(factor), 0.2), 5.0)
        _ = node.setProperty("canvas.zoom", value: .float(next))
    }

    private func applyRotation(delta: CGFloat) {
        let current = Double(view.state.rotation)
        let next = current + Double(delta)
        _ = node.setProperty("canvas.rotation", value: .float(next))
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentSize = NSSize(width: 640, height: 400)
        let frame = NSRect(origin: .zero, size: contentSize)

        let properties: [FGKPropertyDescriptor] = [
            .init(name: "canvas.zoom", kind: .float(min: 0.2, max: 5.0, default: 1.0)),
            .init(name: "canvas.translation.x", kind: .float(min: -1000.0, max: 1000.0, default: 0.0)),
            .init(name: "canvas.translation.y", kind: .float(min: -1000.0, max: 1000.0, default: 0.0)),
            .init(name: "canvas.rotation", kind: .float(min: -Double.pi * 2, max: Double.pi * 2, default: 0.0))
        ]

        let rootNode = FGKNode(
            instrumentId: "fountain.gui.demo.surface",
            frame: frame,
            properties: properties,
            target: nil
        )

        let rootView = DemoSurfaceView(frame: frame, rootNode: rootNode)
        rootView.wantsLayer = true

        let target = DemoInstrumentTarget(view: rootView, node: rootNode)
        rootNode.target = target

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FountainGUIKit Demo (FountainKit)"
        window.contentView = rootView
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

@main
enum FountainGUIDemoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
