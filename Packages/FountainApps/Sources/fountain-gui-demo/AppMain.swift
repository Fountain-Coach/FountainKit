import AppKit
import FountainGUIKit

private final class DemoTarget: FGKEventTarget {
    func handle(event: FGKEvent) -> Bool {
        switch event {
        case .keyDown(let key):
            fputs("[FGKDemo] keyDown chars=\(key.characters) code=\(key.keyCode)\n", stderr)
        case .keyUp(let key):
            fputs("[FGKDemo] keyUp chars=\(key.characters) code=\(key.keyCode)\n", stderr)
        case .mouseDown(let mouse):
            fputs("[FGKDemo] mouseDown at=\(mouse.locationInView)\n", stderr)
        case .mouseUp(let mouse):
            fputs("[FGKDemo] mouseUp at=\(mouse.locationInView)\n", stderr)
        case .mouseMoved(let mouse):
            fputs("[FGKDemo] mouseMoved at=\(mouse.locationInView)\n", stderr)
        case .mouseDragged(let mouse):
            fputs("[FGKDemo] mouseDragged at=\(mouse.locationInView)\n", stderr)
        case .scroll(let scroll):
            fputs("[FGKDemo] scroll dx=\(scroll.deltaX) dy=\(scroll.deltaY) at=\(scroll.locationInView)\n", stderr)
        case .magnify(let magnify):
            fputs("[FGKDemo] magnify m=\(magnify.magnification) at=\(magnify.locationInView)\n", stderr)
        case .rotate(let rotate):
            fputs("[FGKDemo] rotate r=\(rotate.rotation) at=\(rotate.locationInView)\n", stderr)
        case .swipe(let swipe):
            fputs("[FGKDemo] swipe dx=\(swipe.deltaX) dy=\(swipe.deltaY) at=\(swipe.locationInView)\n", stderr)
        }
        return true
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentSize = NSSize(width: 640, height: 400)
        let frame = NSRect(origin: .zero, size: contentSize)

        let rootNode = FGKNode(
            instrumentId: "fountain.gui.demo.surface",
            frame: frame,
            properties: []
        )
        let target = DemoTarget()
        rootNode.target = target

        let rootView = FGKRootView(frame: frame, rootNode: rootNode)
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

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
